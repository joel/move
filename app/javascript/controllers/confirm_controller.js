import { Controller } from "@hotwired/stimulus"

// Native confirm() guard for a form that submits WITHOUT Turbo. Turbo's
// `data-turbo-confirm` only runs when Turbo handles the submission, but a
// destructive action ending in a cross-host redirect (e.g. deleting your account
// from an org subdomain → apex) must submit with `data-turbo="false"` so the
// browser follows the redirect itself — which means we lose turbo-confirm and
// drive the confirmation here instead. Phlex blocks inline on* handlers.
//   form data: { turbo: false, controller: "confirm",
//                confirm_message_value: "…", action: "submit->confirm#confirm" }
export default class extends Controller {
  static values = { message: String }

  confirm(event) {
    if (!window.confirm(this.messageValue)) {
      event.preventDefault()
    }
  }
}
