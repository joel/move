import { Controller } from "@hotwired/stimulus"
import CameraStream from "camera/stream"

// Match the capture-upload pipeline's maxEdge so its own downscale is a no-op
// for viewfinder frames (one encode per shot, here).
const MAX_EDGE = 2048
const JPEG_QUALITY = 0.85
// Two-tier failsafe for the upload lock — together the tiers guarantee both
// "never lose a photo" (#620) and "never lock forever" (#622):
//
// Pre-submit tier: bounds the window where capture-upload can bail before
// requestSubmit (empty selection, stale guard) and no terminal event will
// ever come. Generous versus that window's own worst-case timeouts
// (2.5s downscale + 15s direct upload).
const SETTLE_FAILSAFE_MS = 30000
// In-flight tier: once turbo:submit-start fires, a turbo:submit-end normally
// follows (success, failure, or network error), so the lock holds through
// arbitrarily slow submissions — but a fetch CAN stall without ever erroring,
// and an eternal lock is the one thing worse than the overwrite this lock
// prevents. After this long a still-pending submission is effectively dead
// (browsers surface real stalls as errors well before), so unlocking is the
// deliberate, accepted trade (#622).
const INFLIGHT_RECOVERY_MS = 120000

// #616 — in-app camera viewfinder for the capture screen. The native camera app
// (file input + `capture` attr) rotates to landscape with the device and cannot
// be orientation-locked by a web app; rendering the camera INSIDE the app window
// makes the PWA manifest's portrait lock govern the whole capture experience.
//
// One state machine — idle → requesting → streaming → capturing → streaming,
// plus `unavailable` — with two invariants:
//   1. #setState is the single writer of all state-dependent DOM (visibility +
//      shutter disabled), so a Turbo cache restore (which replays DOM mutated
//      mid-stream) is repaired by connect() simply applying "idle".
//   2. Every await tail re-checks its generation token, and every terminal path
//      releases the stream — an abandoned getUserMedia can never leave the
//      camera indicator lit. The stream side of this lives in the shared
//      camera/stream module (#618); capture() re-checks the same token.
//
// The shutter grabs exactly the frame region the object-cover viewfinder shows
// (what you frame out must not reach recognition) and hands the JPEG to the
// existing capture-upload pipeline by inserting it into the file input and
// dispatching `change` — downscale, direct upload, and submit apply unchanged.
// Because that pipeline is a single-slot input with replace semantics, the
// shutter stays locked from `change` until the form's turbo:submit-end, so a
// burst of shots can never overwrite an in-flight photo (which would silently
// drop it). Grabbed frames are upright by construction — no EXIF to honor.
//
// The camera auto-starts only on coarse pointers (phones/tablets — the page's
// single job is capture); on fine pointers the tile stays primary and a
// "Use camera" button starts the viewfinder on demand, so a desktop webcam
// never lights up unprompted. The same button doubles as the retry affordance
// when the camera fails or dies (`unavailable` is recoverable). While the page
// is hidden the stream is released (battery; iOS freezes backgrounded tracks)
// and re-acquired on return.
export default class extends Controller {
  static targets = ["viewfinder", "video", "shutter", "status", "flash",
    "fallback", "start", "library", "input", "note", "close", "pending"]

  // autostart: false on surfaces where capture is a secondary action (the
  // review screen's Retake, #619) — the camera then starts only from the
  // "start" button on every pointer type, and the optional "close" target
  // releases it again.
  static values = { autostart: { type: Boolean, default: true } }

  connect() {
    this.retried = false
    this.resumeOnVisible = false
    this.resumeAfterCache = false
    // Set by #settle when the focused pending status hides mid-request (#995).
    this.focusOnStarted = false
    this.settleTimer = null
    // The getUserMedia lifecycle (generation guard, track-ended hook, release)
    // is the shared camera/stream module (#618); this controller owns only
    // the capture state machine around it.
    this.camera = new CameraStream(this.videoTarget, {
      constraints: { facingMode: "environment", width: { ideal: MAX_EDGE }, height: { ideal: MAX_EDGE } },
      onEnded: () => this.#trackEnded()
    })
    // The upload lock is deliberately SEPARATE from the camera state machine:
    // a camera interruption (track death, hide/show) must never unlock a busy
    // pipeline — the input is single-slot, and a second submission while one
    // is in flight makes Turbo abort the first (silent photo loss).
    this.uploadPending = false
    this.liveSubmission = null
    this.abandonedSubmissions = new Set()
    this.supported = CameraStream.supported
    this.onVisibility = () => this.#visibilityChanged()
    document.addEventListener("visibilitychange", this.onVisibility)
    this.#setState(this.supported ? "idle" : "unavailable")
    if (this.supported && this.#autostarts()) this.start()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.#clearSettleTimer()
    this.resumeAfterCache = false
    this.camera.stop()
  }

  // turbo:before-cache — release the camera as soon as a navigation caches
  // this page and snapshot it with the viewfinder folded away. The upload
  // lock is untouched (closing never unlocks a busy pipeline). Turbo can also
  // cache WITHOUT replacing the page (#987: a history entry Turbo didn't
  // create, or a morphing refresh), so a camera that was live is remembered
  // and resumed if this controller is still connected afterwards.
  teardown() {
    const live = this.state === "requesting" || this.state === "streaming" || this.state === "capturing"
    if (!live) return
    this.camera.stop()
    this.resumeAfterCache = true
    this.#setState("idle")
  }

  // turbo:load / turbo:render / popstate after a teardown: if the page was
  // not replaced (this element is still mounted), turn the camera back on.
  // popstate covers Turbo's empty-state history pop, which caches the page
  // but fires neither turbo:load nor turbo:render. Deferred one tick: Turbo
  // clones the snapshot on the next event-loop tick after
  // turbo:before-cache, and the restarted "requesting" DOM must not leak
  // into it.
  resume() {
    if (!this.resumeAfterCache) return
    setTimeout(() => {
      if (!this.resumeAfterCache || !this.element.isConnected) return
      this.resumeAfterCache = false
      this.retried = false
      this.start()
    }, 0)
  }

  // Auto-start (coarse pointer), the "Use camera" button, or a retry. The
  // stream module re-checks its generation after every await, so a teardown
  // mid-prompt resolves "stale" and leaves the state to whoever tore down.
  async start() {
    if (!this.supported) return
    if (this.state !== "idle" && this.state !== "unavailable") return
    // The start control hides while the camera is requested; a keyboard user
    // who pressed it must not be left focused on a hidden control. But the
    // permission prompt can stay open a while: if the user has moved focus
    // elsewhere by the time it resolves, the late resolve must not steal it
    // back (#992).
    const fromStart = this.startTarget.contains(document.activeElement)
    this.#setState("requesting")
    const outcome = await this.camera.start()
    // A stale request leaves the handoff to the request that replaces it.
    if (outcome === "stale") return
    const handoff = this.focusOnStarted
    this.focusOnStarted = false
    const refocus = (fromStart || handoff) && this.#focusLeftWithStart()
    if (outcome !== "live") {
      this.#setState("unavailable")
      if (refocus) this.#focusStart()
      return
    }
    this.retried = false
    this.#setState("streaming")
    if (refocus) this.#focusLive()
  }

  // Focus is still where the hidden start control left it: on the control
  // itself, or dropped to the body when it hid.
  #focusLeftWithStart() {
    const active = document.activeElement
    return !active || active === document.body || this.startTarget.contains(active)
  }

  // The shutter, unless an upload in flight keeps it disabled — then the
  // "Replacing photo…" status (Cancel is hidden while the lock is held, #991).
  #focusLive() {
    const target = this.shutterTarget.disabled && this.hasPendingTarget ? this.pendingTarget : this.shutterTarget
    target.focus()
  }

  // "Cancel" (the close target, #619): release the camera and fold the
  // viewfinder away. stop() bumps the generation, so an in-flight start() or
  // capture() tail goes stale. Focus moves to the re-revealed start control
  // (the Cancel button that held it is now hidden). While an upload is
  // pending Cancel is hidden (#991): the in-flight POST would still replace
  // the photo, so "Cancel" would be a lie — and a real abort is out of scope
  // (#622 aborts only on recovery).
  close() {
    if (this.uploadPending) return
    if (this.state === "idle" || this.state === "unavailable") return
    this.camera.stop()
    this.resumeOnVisible = false
    this.#setState("idle")
    this.#focusStart()
  }

  // The start target is the button itself (B2) or a wrapper around a
  // Ui::Button (review Retake).
  #focusStart() {
    const start = this.startTarget
    const button = start.matches("button") ? start : start.querySelector("button")
    button?.focus()
  }

  // Shutter → grab the visible frame → hand it to the capture-upload pipeline.
  // "capturing" covers only the grab; #deliver's change event raises the
  // upload lock, which keeps the shutter down after we return to "streaming".
  async capture() {
    if (this.state !== "streaming" || this.uploadPending) return
    const generation = this.camera.generation
    this.#setState("capturing")
    let blob = null
    try {
      blob = await this.#grabFrame()
    } catch (_error) {
      // Fall through: no frame, no flash — the shutter re-arms below.
    }
    if (!this.camera.isCurrent(generation) || this.state !== "capturing") return
    if (blob) {
      // Feedback only when a frame actually enters the pipeline — a flash on a
      // failed grab would tell the user a photo exists that never will.
      this.#flash()
      this.#deliver(blob)
    }
    this.#setState("streaming")
  }

  // Any `change` on the file input carrying a real selection (our own #deliver
  // or a library/tile pick) starts an upload: raise the lock until it settles.
  // A cancelled picker can fire `change` with an empty selection — no lock, or
  // the shutter would sit dead for the whole failsafe window.
  uploadStarted() {
    if (!this.inputTarget.files?.length) return
    // The lock disables the shutter and hides Library/Cancel — a keyboard
    // user on one of them would drop to the body (some browsers already blur
    // the shutter while "capturing" disables it); move them to the pending
    // status instead, where there is one.
    const stranded = this.#lockHides(document.activeElement)
    this.uploadPending = true
    this.#armSettleTimer(SETTLE_FAILSAFE_MS)
    this.#setState(this.state)
    if (stranded && this.hasPendingTarget) this.pendingTarget.focus()
  }

  #lockHides(element) {
    if (!element || element === document.body) return true
    return element === this.shutterTarget || element === this.libraryTarget ||
      (this.hasCloseTarget && element === this.closeTarget)
  }

  // turbo:submit-start — the form is genuinely in flight: remember WHICH
  // submission is live (a recovery-abandoned one can still emit its terminal
  // event later, and only the live one may settle the lock), and swap the
  // pre-submit failsafe for the much longer in-flight recovery tier, so a
  // slow POST never unlocks a busy pipeline (#620) while a hung one can't
  // lock it forever (#622).
  uploadInFlight(event) {
    if (!this.uploadPending) return
    this.liveSubmission = event.detail?.formSubmission || null
    this.#armSettleTimer(INFLIGHT_RECOVERY_MS)
  }

  // turbo:submit-end — but a zombie's late terminal event (its submission was
  // abandoned by the recovery tier) must never settle a NEWER capture's lock
  // nor reset its input, whether that capture is already in flight (the
  // liveSubmission check) or still pre-submit (the abandonedSubmission
  // check) — either would recreate the photo loss #620 closed. An event
  // without a formSubmission detail settles normally — never worse than
  // before this demux existed.
  uploadSettled(event) {
    const submission = event?.detail?.formSubmission
    if (submission && this.abandonedSubmissions.delete(submission)) return
    if (this.liveSubmission && submission && submission !== this.liveSubmission) return
    this.#settle()
  }

  // A failsafe tier expired — no terminal event came. Abort the abandoned
  // submission outright (FormSubmission#stop cancels its fetch, so a
  // late-completing response can never be rendered and navigate the page out
  // from under a replacement capture), and remember it in a Set as
  // defense-in-depth for the terminal event the abort itself emits — or for
  // a Turbo version where stop() is unavailable. A Set, not a slot: a later
  // pre-submit recovery carries no live submission and must not erase an
  // earlier zombie's identity. Entries are consumed as terminal events
  // arrive; each costs a 120s hang, so the set stays tiny.
  #recoverFromHang() {
    if (this.liveSubmission) {
      this.abandonedSubmissions.add(this.liveSubmission)
      try {
        this.liveSubmission.stop?.()
      } catch (_error) {
        // The demux still ignores its terminal event; worst case is the old
        // pre-abort behavior.
      }
    }
    this.#settle()
  }

  // The single settle path: release the lock and ask capture-upload to reset
  // (re-enable input, clear value + signed_id). The reset ride-along matters
  // on BOTH paths — after a genuine settle it is the normal post-submit
  // cleanup; after a recovery the pipeline may be wedged mid-flight with its
  // input disabled and a stale signed_id (direct-upload mode), and clearing
  // the input also makes any zombie submit() bail on its own staleness
  // guards. The event bubbles from the input to the form, where
  // capture-upload listens.
  //
  // When the page stays mounted (a failed response rendered in place, or a
  // recovery), the "Replacing photo…" status hides here; if it held focus,
  // the keyboard user must not drop to the body (#995).
  #settle() {
    const stranded = this.hasPendingTarget && this.pendingTarget.contains(document.activeElement)
    this.liveSubmission = null
    this.#clearSettleTimer()
    this.uploadPending = false
    this.inputTarget.dispatchEvent(new CustomEvent("camera-capture:settle", { bubbles: true }))
    this.#setState(this.state)
    if (stranded) this.#focusAfterSettle()
  }

  // The next live control: the re-armed shutter while streaming, else the
  // start control (idle, or the retry after a failure), else the chooser.
  // Mid-request (an automatic re-acquire) none is on show yet: start() hands
  // focus over when the request resolves.
  #focusAfterSettle() {
    if (this.state === "requesting") {
      this.focusOnStarted = true
      return
    }
    if (this.state === "streaming") return this.shutterTarget.focus()
    if (this.#offerStart(this.state)) return this.#focusStart()
    if (!this.fallbackTarget.classList.contains("hidden")) this.inputTarget.focus()
  }

  // "Choose from library" — the same input the tile wraps; the existing
  // change→capture-upload#submit wiring takes it from there. A button (not a
  // label) so it is keyboard-focusable.
  openLibrary() {
    if (this.uploadPending) return
    this.inputTarget.click()
  }

  // The one choke point every picker path funnels through (tile label tap,
  // keyboard activation of the input, openLibrary's click()): a file input's
  // click is cancelable before the dialog opens, so this makes the upload lock
  // airtight — a pick during a pending upload would overwrite the single-slot
  // input and abort the in-flight photo.
  guardPick(event) {
    if (this.uploadPending) event.preventDefault()
  }

  // The camera died mid-session (OS reclaimed it, permission revoked) — in any
  // live state, including the requesting/play() window (an unhandled death
  // there would leave "streaming" armed over a corpse). Hidden → resume on
  // return; visible → one automatic re-acquire per incident, then give up to
  // the tile (with "Use camera" as the manual retry). The upload lock is
  // untouched: an in-flight photo keeps the shutter down across the recovery.
  // (The stream module only calls this for the current stream's tracks.)
  #trackEnded() {
    if (this.state === "idle" || this.state === "unavailable") return
    this.camera.stop() // invalidates any in-flight start()/capture() tail on this stream
    if (document.hidden) {
      this.resumeOnVisible = true
      return this.#setState("idle")
    }
    if (this.retried) return this.#setState("unavailable")
    this.retried = true
    this.#setState("idle")
    this.start()
  }

  // Release the camera while the page is hidden (battery; a backgrounded track
  // freezes on iOS and would capture stale frames) and re-acquire on return.
  #visibilityChanged() {
    if (document.hidden) {
      if (this.state === "requesting" || this.state === "streaming" || this.state === "capturing") {
        this.camera.stop()
        this.resumeOnVisible = true
        this.#setState("idle")
      }
    } else if (this.resumeOnVisible) {
      this.resumeOnVisible = false
      this.retried = false
      this.start()
    }
  }

  // Grab exactly what the viewfinder shows: the object-cover crop of the video
  // frame (centered, like object-position's default), capped at MAX_EDGE.
  async #grabFrame() {
    const video = this.videoTarget
    if (video.readyState < video.HAVE_CURRENT_DATA || !video.videoWidth) return null
    const box = video.getBoundingClientRect()
    let srcWidth = video.videoWidth
    let srcHeight = video.videoHeight
    if (box.width > 0 && box.height > 0) {
      const cover = Math.max(box.width / video.videoWidth, box.height / video.videoHeight)
      srcWidth = Math.min(video.videoWidth, Math.round(box.width / cover))
      srcHeight = Math.min(video.videoHeight, Math.round(box.height / cover))
    }
    const srcX = Math.floor((video.videoWidth - srcWidth) / 2)
    const srcY = Math.floor((video.videoHeight - srcHeight) / 2)
    const scale = Math.min(1, MAX_EDGE / Math.max(srcWidth, srcHeight))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(srcWidth * scale)
    canvas.height = Math.round(srcHeight * scale)
    canvas.getContext("2d")
      .drawImage(video, srcX, srcY, srcWidth, srcHeight, 0, 0, canvas.width, canvas.height)
    return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY))
  }

  // Insert the frame into the file input and fire `change` — from here the
  // capture-upload controller owns the photo exactly as if the user had picked
  // it. Assigning input.files does not fire `change` itself (see
  // capture_upload_controller#replaceFile), so this single dispatch is the only
  // submit trigger; it also bubbles to uploadStarted, which keeps the shutter
  // locked for the upload window.
  #deliver(blob) {
    const file = new File([blob], `capture-${Date.now()}.jpg`, { type: "image/jpeg" })
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.inputTarget.files = transfer.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Keep the 150ms in sync with the flash layer's duration-150 class (show.rb).
  #flash() {
    const flash = this.flashTarget
    flash.classList.remove("opacity-0")
    setTimeout(() => flash.classList.add("opacity-0"), 150)
  }

  // The single writer of state-dependent DOM. Everything each state shows is
  // derived here, in one table (which also reads the orthogonal upload lock) —
  // never toggle these classes anywhere else.
  #setState(state) {
    this.state = state
    const streaming = state === "streaming" || state === "capturing"
    const live = streaming || state === "requesting"
    this.viewfinderTarget.classList.toggle("hidden", !live)
    this.statusTarget.classList.toggle("hidden", state !== "requesting")
    this.fallbackTarget.classList.toggle("hidden", live)
    // The tile can be on show while an upload is pending (camera interruption
    // mid-upload lands back in idle/unavailable) — render it inert; guardPick
    // is the functional block.
    this.fallbackTarget.classList.toggle("pointer-events-none", this.uploadPending)
    this.fallbackTarget.classList.toggle("opacity-50", this.uploadPending)
    this.libraryTarget.classList.toggle("hidden", !streaming || this.uploadPending)
    this.noteTarget.classList.toggle("hidden", state !== "unavailable")
    this.startTarget.classList.toggle("hidden", !this.#offerStart(state))
    // Cancel can't cancel an upload already handed to the pipeline (#991):
    // hide it while the lock is held and say what is happening instead.
    if (this.hasCloseTarget) this.closeTarget.classList.toggle("hidden", !live || this.uploadPending)
    if (this.hasPendingTarget) this.pendingTarget.classList.toggle("hidden", !this.uploadPending)
    this.shutterTarget.disabled = state !== "streaming" || this.uploadPending
  }

  // "Use camera" shows on idle whenever the camera doesn't auto-start (fine
  // pointers — no unprompted webcam — or an autostart: false surface) and as
  // the retry affordance whenever the camera failed but the API exists.
  #offerStart(state) {
    if (!this.supported) return false
    if (state === "unavailable") return true
    return state === "idle" && !this.#autostarts()
  }

  #autostarts() {
    return this.autostartValue && window.matchMedia("(pointer: coarse)").matches
  }

  // One failsafe at a time — re-arming without clearing would orphan a timer
  // that later fires recovery in the middle of a subsequent upload.
  #armSettleTimer(ms) {
    this.#clearSettleTimer()
    this.settleTimer = setTimeout(() => this.#recoverFromHang(), ms)
  }

  #clearSettleTimer() {
    if (this.settleTimer) {
      clearTimeout(this.settleTimer)
      this.settleTimer = null
    }
  }
}
