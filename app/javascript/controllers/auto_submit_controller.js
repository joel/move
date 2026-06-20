import { Controller } from "@hotwired/stimulus"

// Submits the controller's form when an input fires its bound event — e.g. a
// role <select> that applies on change (F1 Members & Roles). Phlex blocks inline
// on* handlers, so the auto-submit lives here.
//   form_with(..., data: { controller: "auto-submit" })
//   select(..., data: { action: "change->auto-submit#submit" })
//
// Opt-in: submit once on connect. Used to auto-start Google OAuth on the apex
// when a subdomain routed the user here with ?via=google.
//   form data: { controller: "auto-submit", auto_submit_on_connect_value: true }
export default class extends Controller {
  static values = { onConnect: Boolean }

  connect() {
    if (this.onConnectValue) this.submit()
  }

  submit() {
    this.element.requestSubmit()
  }
}
