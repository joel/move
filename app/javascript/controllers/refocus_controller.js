import { Controller } from "@hotwired/stimulus"

// Restores keyboard/AT focus after a Turbo Stream re-renders the control the
// user activated (#727 — the B1 in-place unpacking toggles). Submitting a
// button_to disables its button mid-flight, which drops focus to <body>
// BEFORE the stream lands, so neither replace nor morph can preserve it.
// Capture the submitter's stable id at submit-start (only for forms inside
// this controller's element), then refocus that id once the submission ends
// and the stream has been applied.
//
// Listeners are attached to document in connect() (not via data-action) so
// the Stimulus scope trap can't silently disable them; the element.contains
// guard keeps the capture scoped to this surface.
export default class extends Controller {
  connect() {
    this.pendingId = null
    this.containerId = null
    this.onSubmitStart = (event) => {
      const submitter = event.detail?.formSubmission?.submitter
      if (!submitter?.id || !this.element.contains(event.target)) return
      this.pendingId = submitter.id
      // Fallback anchor: the card the control lives in. A successful bulk
      // "Unpack photo" removes its own button, so focus must land on the
      // nearest surviving control (e.g. the first restore chip) instead.
      this.containerId = submitter.closest("[id^='box_photo_'], [id^='box_item_']")?.id ?? null
    }
    this.onSubmitEnd = () => {
      const id = this.pendingId
      const containerId = this.containerId
      this.pendingId = null
      this.containerId = null
      if (!id) return
      // Streams render synchronously on message receipt; the double rAF waits
      // out the current frame so the swapped/morphed node is in the DOM.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const target = document.getElementById(id) ||
          document.getElementById(containerId ?? "")?.querySelector("button, a[href]")
        target?.focus()
      }))
    }
    document.addEventListener("turbo:submit-start", this.onSubmitStart)
    document.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-start", this.onSubmitStart)
    document.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }
}
