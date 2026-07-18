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
export default class extends Controller {
  static targets = ["form", "input"]

  // Submit of either "Mark as Reviewed" button_to form.
  guardSubmit(event) {
    if (this.resuming) {
      this.resuming = false
      return
    }
    if (this.awaitingAdd) {
      event.preventDefault() // a second advance while the add is in flight is noise
      return
    }
    if (!this.#pending()) return

    event.preventDefault()
    this.#addThen(() => {
      this.resuming = true
      event.target.requestSubmit()
    })
  }

  // Click on the Ignore / Next / Finish anchors.
  guardVisit(event) {
    if (this.awaitingAdd) {
      event.preventDefault()
      return
    }
    if (!this.#pending()) return

    event.preventDefault()
    const href = event.currentTarget.href
    this.#addThen(() => this.#visit(href))
  }

  #pending() {
    return this.hasInputTarget && this.inputTarget.value.trim() !== ""
  }

  // Submit the add form; run `resume` only if it succeeded. The once-listener
  // is consumed on success or failure, so a retry never stacks resumes.
  #addThen(resume) {
    this.awaitingAdd = true
    this.formTarget.addEventListener(
      "turbo:submit-end",
      (event) => {
        this.awaitingAdd = false
        if (event.detail.success === false) return
        resume()
      },
      { once: true }
    )
    this.formTarget.requestSubmit()
  }

  #visit(url) {
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }
}
