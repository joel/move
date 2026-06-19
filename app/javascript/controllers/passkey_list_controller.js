import { Controller } from "@hotwired/stimulus"

// Augments the manage-passkeys page with browser memory. The server already
// badges the passkey this session signed in with (authenticated_webauthn_id);
// this also badges passkeys THIS browser registered (recorded in localStorage by
// the setup JS), which covers email-link sessions where the server has no signal.
// When this browser is known to hold a passkey, hide the "Add another" card.
//
//   div(data: { controller: "passkey-list", passkey_list_account_value: id })
//     label(data: { passkey_list_target: "row", webauthn_id: id })
//       span(data: { passkey_list_target: "badge" }, class: "hidden") { "This device" }
//     div(data: { passkey_list_target: "addCard" })
export default class extends Controller {
  static targets = ["row", "badge", "addCard"]
  static values = { account: String }

  connect() {
    const ids = this.storedIds()
    let deviceHasPasskey = false

    this.rowTargets.forEach((row) => {
      const badge = row.querySelector('[data-passkey-list-target="badge"]')
      const alreadyMarked = badge && !badge.classList.contains("hidden")
      if (alreadyMarked) deviceHasPasskey = true // server marked the current row

      if (ids.includes(row.dataset.webauthnId)) {
        deviceHasPasskey = true
        row.classList.add("ring-2", "ring-[var(--ha-primary)]")
        if (badge) badge.classList.remove("hidden")
      }
    })

    if (deviceHasPasskey && this.hasAddCardTarget) {
      this.addCardTarget.classList.add("hidden")
    }
  }

  storedIds() {
    try {
      return JSON.parse(localStorage.getItem(`move.passkeys.${this.accountValue}`) || "[]")
    } catch (e) {
      return []
    }
  }
}
