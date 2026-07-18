import { Controller } from "@hotwired/stimulus"

// Per-photo review (C2/#690): typed-but-unsubmitted "add a missed item" text
// must not be silently discarded by the advance controls (Mark as Reviewed /
// Ignore / Next / Finish). When the add field holds text, hold the advance,
// submit the add form, and resume the original advance once the add succeeds —
// auto-add, then advance. A failed add (422) drops the resume and stays on the
// page: the existing error toast + retained text explain, and retrying the
// advance just repeats the attempt.
//
// Scoped on the items panel (editable pages only): both AdvanceControls
// instances (header + footer) bubble their events through it. Turbo's own
// window-level submit/click handlers run in the bubble phase after these
// actions and stand down on defaultPrevented, so preventDefault() here cleanly
// stops both the native submission and Turbo (verified against Turbo 8.0.23).
// reset-form blanks the input on the add's success before the resume runs; the
// `resuming` flag makes re-interception impossible regardless of ordering.
//
// The add form reports its own submissions via addStarted/addEnded
// (turbo:submit-start/end actions), so a manual ✓ submission already in
// flight is never resubmitted — the guard just queues the advance behind it.
export default class extends Controller {
  static targets = ["form", "input"]

  // A queued advance must yield to any navigation the user starts while the
  // add is still in flight (back arrow, queue badge, another form): the old
  // page stays connected until the destination renders, so DOM detachment
  // alone can't catch an add that settles inside that window. The add form's
  // own submissions are excluded — #addThen arms the resume before submitting.
  connect() {
    this.cancelQueued = (event) => {
      if (this.hasFormTarget && event.target === this.formTarget) return
      this.queuedResume = null
    }
    document.addEventListener("turbo:before-visit", this.cancelQueued)
    document.addEventListener("turbo:submit-start", this.cancelQueued)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.cancelQueued)
    document.removeEventListener("turbo:submit-start", this.cancelQueued)
  }

  // Submit of either "Mark as Reviewed" button_to form.
  guardSubmit(event) {
    if (this.resuming) {
      this.resuming = false
      return
    }
    if (this.resumeArmed) {
      event.preventDefault() // a second advance while one is queued is noise
      return
    }
    if (!this.#pending()) return

    event.preventDefault()
    this.#addThen(() => {
      this.resuming = true
      event.target.requestSubmit()
    })
  }

  // Click on the Ignore / Next / Finish anchors. Modified clicks (new tab /
  // window) keep their browser semantics — Turbo ignores them too, and the
  // typed text survives on the current page either way.
  guardVisit(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (this.resumeArmed) {
      event.preventDefault()
      return
    }
    if (!this.#pending()) return

    event.preventDefault()
    const href = event.currentTarget.href
    this.#addThen(() => this.#visit(href))
  }

  // The add form's own Turbo submission lifecycle (fires for manual ✓ / Enter
  // submissions as well as the guard's requestSubmit). addStarted opens a
  // revision window — inputEdited marks any user edit inside it (value
  // comparison would miss a deliberately re-typed duplicate name, which is
  // valid) — and addEnded snapshots whatever the input holds at settle time.
  // addEnded is wired BEFORE reset-form#reset in the form's data-action, so
  // the snapshot is taken before a successful add wipes the field; text typed
  // while the earlier add was in flight survives in it and gets its own
  // submission (see #addThen).
  addStarted() {
    this.addInFlight = true
    this.editedSinceSubmit = false
  }

  addEnded() {
    this.addInFlight = false
    this.settleValue = this.hasInputTarget ? this.inputTarget.value.trim() : ""
  }

  inputEdited() {
    this.editedSinceSubmit = true
  }

  #pending() {
    return this.hasInputTarget && this.inputTarget.value.trim() !== ""
  }

  // Queue `resume` behind the add: submit the form unless a submission is
  // already in flight (a manual ✓ the user beat us to — resubmitting would
  // create the item twice), then run `resume` when it succeeds. The
  // once-listener is consumed on success or failure, so a retry never stacks
  // resumes. Two staleness guards: cancelQueued drops the resume when the
  // user starts another navigation while the old page is still connected, and
  // the connectedness check drops it once teardown has happened (Turbo visits
  // keep the JS context alive, so the listener still fires on a detached
  // form) — either way the user is never yanked off the page they chose.
  #addThen(resume) {
    this.resumeArmed = true
    this.queuedResume = resume
    this.formTarget.addEventListener(
      "turbo:submit-end",
      (event) => {
        this.resumeArmed = false
        const queued = this.queuedResume
        this.queuedResume = null
        if (event.detail.success === false) return
        if (!this.element.isConnected) return
        // The user typed another item while the earlier add was in flight:
        // reset-form just wiped it, but addEnded snapshotted it — restore the
        // field and converge with another add before advancing.
        if (queued && this.settleValue && this.editedSinceSubmit) {
          this.inputTarget.value = this.settleValue
          this.#addThen(queued)
          return
        }
        queued?.()
      },
      { once: true }
    )
    if (!this.addInFlight) this.formTarget.requestSubmit()
  }

  #visit(url) {
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }
}
