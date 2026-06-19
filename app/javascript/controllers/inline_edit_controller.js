import { Controller } from "@hotwired/stimulus"

// Toggles a read-only display panel <-> an inline edit form (e.g. renaming the
// account name from the profile panel). The form submits normally (Turbo PATCH);
// `openValue` keeps the form open on re-render when the submit failed validation.
//
//   div(data: { controller: "inline-edit", inline_edit_open_value: errors? })
//     div(data: { inline_edit_target: "display" }) { name; pencil → edit }
//     div(class: "hidden", data: { inline_edit_target: "form" }) { form; cancel }
export default class extends Controller {
  static targets = ["display", "form", "input"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.edit()
  }

  edit() {
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    if (this.hasInputTarget) {
      this.inputTarget.focus()
      this.inputTarget.select()
    }
  }

  cancel() {
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }
}
