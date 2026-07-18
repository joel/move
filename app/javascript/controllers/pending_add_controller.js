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
  // submissions as well as the guard's requestSubmit).
  addStarted() {
    this.addInFlight = true
  }

  addEnded() {
    this.addInFlight = false
  }

  #pending() {
    return this.hasInputTarget && this.inputTarget.value.trim() !== ""
  }

  // Queue `resume` behind the add: submit the form unless a submission is
  // already in flight (a manual ✓ the user beat us to — resubmitting would
  // create the item twice), then run `resume` when it succeeds. The
  // once-listener is consumed on success or failure, so a retry never stacks
  // resumes. Turbo visits keep the JS context alive, so if the user left
  // through an unguarded control (back arrow, queue badge) while the add was
  // in flight, the listener still fires on the detached form — the
  // connectedness check drops the stale resume instead of yanking them off
  // the page they deliberately went to.
  #addThen(resume) {
    this.resumeArmed = true
    this.formTarget.addEventListener(
      "turbo:submit-end",
      (event) => {
        this.resumeArmed = false
        if (event.detail.success === false) return
        if (!this.element.isConnected) return
        resume()
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
