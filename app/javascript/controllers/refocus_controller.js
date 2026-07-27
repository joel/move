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
    this.ancestorIds = []
    this.onSubmitStart = (event) => {
      const submitter = event.detail?.formSubmission?.submitter
      if (!submitter?.id || !this.element.contains(event.target)) return
      this.pendingId = submitter.id
      // Fallback anchors: every identified ancestor, nearest first. Whichever
      // survives the stream hosts focus when the submitter itself was removed
      // — a bulk "Unpack photo" removes its own button (card survives), a
      // find-list row unpin removes the whole row (the list wrapper survives).
      this.ancestorIds = []
      let node = submitter.parentElement?.closest("[id]") ?? null
      while (node && this.element.contains(node)) {
        this.ancestorIds.push(node.id)
        node = node.parentElement?.closest("[id]") ?? null
      }
    }
    this.onSubmitEnd = () => {
      const id = this.pendingId
      const ancestorIds = this.ancestorIds
      this.pendingId = null
      this.ancestorIds = []
      if (!id) return
      // Streams render synchronously on message receipt; the double rAF waits
      // out the current frame so the swapped/morphed node is in the DOM.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const host = ancestorIds.map((aid) => document.getElementById(aid)).find(Boolean)
        const target = document.getElementById(id) || host?.querySelector("button, a[href]")
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
