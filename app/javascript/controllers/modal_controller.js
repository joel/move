import { Controller } from "@hotwired/stimulus"

// Reusable native-<dialog> modal (B1 seal flow). The trigger button and the
// <dialog> live inside one data-controller="modal" element:
//
//   div(data: { controller: "modal" })
//     button(data: { action: "modal#open" })
//     dialog(data: { modal_target: "dialog", action: "click->modal#backdropClose" })
//
// showModal() gives focus-trap, Escape-to-close and a ::backdrop for free; we
// only add click-outside-to-close. Close buttons inside the dialog use
// data-action="modal#close".
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  // A click whose target is the <dialog> itself (not its content) is the backdrop.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
