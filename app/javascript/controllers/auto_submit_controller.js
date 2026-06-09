import { Controller } from "@hotwired/stimulus"

// Submits the controller's form when an input fires its bound event — e.g. a
// role <select> that applies on change (F1 Members & Roles). Phlex blocks inline
// on* handlers, so the auto-submit lives here.
//   form_with(..., data: { controller: "auto-submit" })
//   select(..., data: { action: "change->auto-submit#submit" })
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
