import { Controller } from "@hotwired/stimulus"

// Swipe-to-reveal row actions (Ui::SwipeActions): the content layer follows the
// pointer horizontally to reveal the leading (swipe right, e.g. Edit) or
// trailing (swipe left, e.g. Remove) option layer beneath it.
//
//   div(data: { controller: "swipe-actions",
//               action: "turbo:before-cache@document->swipe-actions#teardown
//                        focusout->swipe-actions#closeIfFocusLeft" })
//     div(data: { swipe_actions_target: "leading",
//                 action: "focusin->swipe-actions#open" })  // optional
//     div(data: { swipe_actions_target: "trailing",
//                 action: "focusin->swipe-actions#open" })  // optional
//     div(data: { swipe_actions_target: "content",
//                 action: "pointerdown->swipe-actions#start ..." })
//
// Gesture model: `touch-action: pan-y` (on .ha-swipe-content) leaves vertical
// scrolling to the browser — a scroll that wins delivers pointercancel and we
// snap back. A gesture becomes ours only after an 8px mostly-horizontal lock;
// from there the content tracks the finger 1:1 (CSS transition disabled via
// data-swipe-state="dragging") and snaps open/closed on release by distance
// (half the layer width) or flick velocity. States: closed | dragging |
// open-leading | open-trailing, kept on data-swipe-state (single source; CSS
// keys off it too).
//
// Desktop gating is CSS-owned: the option layers are `lg:hidden`, and start()
// checks their actual computed visibility (offsetParent), so a customized
// --breakpoint-lg can never desync the gesture from the layers. The shared
// breakpoint listener below only resets open rows when the viewport crosses
// lg — a cosmetic heuristic, not the gate.
//
// Concurrency/lifecycle: one row open per page via module state (importmap
// serves a single module instance). Locking a drag claims openRow immediately,
// so a row wedged mid-drag (pointer lost without pointerup/pointercancel) is
// closed by the next row's gesture or by the module-level tap-outside
// listener. A row removed or replaced by a Turbo Stream mid-gesture just
// disconnects (element removal releases any pointer capture); teardown()
// resets before Turbo snapshots the page and when the viewport crosses lg.
let openRow = null

const LOCK_DISTANCE = 8 // px of travel before the gesture is claimed as horizontal
const FLICK_VELOCITY = 0.3 // px/ms — a quick flick opens/closes regardless of distance
const VELOCITY_MAX_AGE = 100 // ms — a release after a still hold is not a flick
const SUPPRESS_CLICK_WINDOW = 500 // ms — swallow the ghost click after a drag, never a later tap
const RUBBER_BAND = 0.2 // drag resistance past the fully-open offset
// Tailwind `lg`, used ONLY for the reset-on-resize heuristic (see header).
const DESKTOP_MQL = window.matchMedia("(min-width: 64rem)")

// Tap/click anywhere outside the open row dismisses it (iOS idiom). One
// module-level listener; openRow is maintained by the instances.
document.addEventListener("pointerdown", (event) => {
  if (openRow && !openRow.element.contains(event.target)) openRow.close()
})

export default class extends Controller {
  static targets = ["content", "leading", "trailing"]

  connect() {
    this.offset = 0
    this.pointerId = null
    this.suppressClicksBefore = 0
    this.setState("closed")
    // Resizing to desktop while open would leave the content translated with
    // the option layers hidden — reset whenever the breakpoint flips.
    this.onBreakpointChange = () => this.teardown()
    DESKTOP_MQL.addEventListener("change", this.onBreakpointChange)
  }

  disconnect() {
    DESKTOP_MQL.removeEventListener("change", this.onBreakpointChange)
    if (openRow === this) openRow = null
  }

  get state() {
    return this.element.dataset.swipeState || "closed"
  }

  // -- pointer gesture -------------------------------------------------------

  start(event) {
    if (!event.isPrimary || this.layersHidden()) return
    // A new primary pointer always resets tracking: a mouse released outside
    // the row (no capture before lock) never delivered pointerup, so treat the
    // previous gesture as abandoned rather than wedging the controller.
    this.pointerId = event.pointerId
    this.startX = event.clientX
    this.startY = event.clientY
    this.startOffset = this.offset
    this.startState = this.state
    this.leadingW = this.layerWidth("leading")
    this.trailingW = this.layerWidth("trailing")
    this.locked = false
    this.ignored = false
    this.lastX = event.clientX
    this.lastT = event.timeStamp
    this.velocity = 0
    // Tapping an open row must close it, not act on what's under the finger:
    // preventDefault kills the compatibility mousedown (so the name input
    // doesn't focus); guardClick swallows the click; pan-y still scrolls.
    if (this.state !== "closed") event.preventDefault()
  }

  move(event) {
    if (event.pointerId !== this.pointerId || this.ignored) return
    const dx = event.clientX - this.startX
    const dy = event.clientY - this.startY
    if (!this.locked) {
      // Vertical intent: leave the gesture to the browser (pan-y scroll) —
      // it will pointercancel us. Nothing has been translated yet.
      if (Math.abs(dy) > Math.abs(dx)) {
        this.ignored = true
        return
      }
      if (Math.abs(dx) < LOCK_DISTANCE) return
      this.locked = true
      this.setState("dragging")
      // Claiming the drag also claims openRow, so a wedged mid-drag row (a
      // pointer lost without a terminal event) is closed by the next gesture.
      if (openRow && openRow !== this) openRow.close()
      openRow = this
      // Capture keeps the drag tracking outside the row. Synthetic
      // PointerEvents (agent-browser eval) have no active pointer and make
      // this throw NotFoundError — capture is an optimisation, not a
      // requirement, so ignore the failure.
      try {
        this.contentTarget.setPointerCapture(event.pointerId)
      } catch {
        // no live pointer to capture
      }
    }
    event.preventDefault()
    const dt = event.timeStamp - this.lastT
    if (dt > 0) this.velocity = (event.clientX - this.lastX) / dt
    this.lastX = event.clientX
    this.lastT = event.timeStamp
    this.translate(this.clamp(this.startOffset + dx))
  }

  end(event) {
    if (event.pointerId !== this.pointerId) return
    this.pointerId = null
    if (!this.locked) {
      // A plain tap. On an open row it closes it; guardClick then swallows
      // the click so nothing underneath activates.
      if (this.state !== "closed") {
        this.close()
        this.suppressClicksBefore = event.timeStamp + SUPPRESS_CLICK_WINDOW
      }
      return
    }
    this.suppressClicksBefore = event.timeStamp + SUPPRESS_CLICK_WINDOW
    // Velocity is only written by pointermove; after a still hold it is
    // stale and the release must count as distance, not as a flick.
    if (event.timeStamp - this.lastT > VELOCITY_MAX_AGE) this.velocity = 0
    this.snapTo(this.targetState())
  }

  cancel(event) {
    if (event.pointerId !== this.pointerId) return
    this.pointerId = null
    if (!this.locked) return
    // The browser claimed the gesture (vertical scroll won) — snap back to
    // where the drag started. No click follows a pointercancel.
    this.snapTo(this.startState)
  }

  // Swallow the ghost click that follows a drag or a tap-to-close, so what is
  // under the finger (name input, buttons) doesn't activate. Capture phase;
  // time-bounded so the guard can never eat an unrelated later tap.
  guardClick(event) {
    if (event.timeStamp >= this.suppressClicksBefore) return
    this.suppressClicksBefore = 0
    event.preventDefault()
    event.stopPropagation()
  }

  // -- open/close ------------------------------------------------------------

  // Closing also revokes any in-flight gesture on this row: a close can
  // arrive externally (tap-away listener, another row locking) while a drag
  // is still tracking, and a dead pointerId keeps move()/cancel() from
  // resurrecting the closed row.
  close() {
    this.pointerId = null
    this.locked = false
    this.snapTo("closed")
  }

  // Keyboard/AT path (focusin on a layer): an occluded option button that
  // receives focus snaps its side open so the focused control is visible.
  open(event) {
    const side =
      this.hasLeadingTarget && event.currentTarget === this.leadingTarget
        ? "open-leading"
        : "open-trailing"
    if (this.state !== side) this.snapTo(side)
  }

  // Focus arriving in the content while a side is open (e.g. Tab moving from
  // an option button to the name input) closes the row so the newly focused
  // control isn't left translated and clipped.
  closeFromContent() {
    if (this.state === "open-leading" || this.state === "open-trailing") this.close()
  }

  closeIfFocusLeft(event) {
    if (this.state === "closed" || this.state === "dragging") return
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return
    this.close()
  }

  // Reset for Turbo's page snapshot and for breakpoint flips: never leave a
  // translated content layer behind.
  teardown() {
    this.pointerId = null
    this.locked = false
    this.suppressClicksBefore = 0
    this.setState("closed")
    this.translate(0)
    if (openRow === this) openRow = null
  }

  // -- internals ---------------------------------------------------------------

  snapTo(state) {
    this.setState(state) // leaves "dragging" first, re-enabling the CSS snap transition
    if (state === "open-leading") this.translate(this.layerWidth("leading"))
    else if (state === "open-trailing") this.translate(-this.layerWidth("trailing"))
    else this.translate(0)
    if (state === "closed") {
      if (openRow === this) openRow = null
    } else {
      if (openRow && openRow !== this) openRow.close()
      openRow = this
    }
  }

  targetState() {
    const width = this.offset > 0 ? this.leadingW : this.trailingW
    if (this.offset === 0 || width === 0) return "closed"
    const open = this.offset > 0 ? "open-leading" : "open-trailing"
    const toward = this.offset > 0 ? this.velocity : -this.velocity // px/ms toward open
    if (toward <= -FLICK_VELOCITY) return "closed" // flicked back shut
    if (toward >= FLICK_VELOCITY) return open // flicked open
    return Math.abs(this.offset) >= width / 2 ? open : "closed"
  }

  setState(state) {
    this.element.dataset.swipeState = state
  }

  translate(offset) {
    this.offset = offset
    this.contentTarget.style.transform = offset === 0 ? "" : `translateX(${offset}px)`
  }

  // A missing layer hard-clamps its side to 0 (nothing to reveal); past the
  // open width of an existing layer the drag rubber-bands. Widths are cached
  // at gesture start — fixed w-24 layers can't change mid-drag, and reading
  // offsetWidth per pointermove would force layout in the hot path.
  clamp(offset) {
    if (offset > 0 && this.leadingW === 0) return 0
    if (offset < 0 && this.trailingW === 0) return 0
    if (offset > this.leadingW) return this.leadingW + (offset - this.leadingW) * RUBBER_BAND
    if (offset < -this.trailingW) return -this.trailingW + (offset + this.trailingW) * RUBBER_BAND
    return offset
  }

  layerWidth(side) {
    if (side === "leading") return this.hasLeadingTarget ? this.leadingTarget.offsetWidth : 0
    return this.hasTrailingTarget ? this.trailingTarget.offsetWidth : 0
  }

  // The option layers are `lg:hidden`; their computed visibility IS the
  // desktop/mobile gate (offsetParent is null for display:none).
  layersHidden() {
    const layer = this.hasLeadingTarget
      ? this.leadingTarget
      : this.hasTrailingTarget && this.trailingTarget
    return !layer || layer.offsetParent === null
  }
}
