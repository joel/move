import { Controller } from "@hotwired/stimulus"
import { NO_ACCOUNT_KEY } from "controllers/one_tap_constants"

export default class extends Controller {
  static values = {
    clientId: String,
    loginPath: String
  }

  connect() {
    if (sessionStorage.getItem(NO_ACCOUNT_KEY)) return

    this.loadScript().then(() => this.initializeOneTap())
  }

  disconnect() {
    if (window.google?.accounts?.id) {
      window.google.accounts.id.cancel()
    }
  }

  loadScript() {
    return new Promise((resolve) => {
      if (window.google?.accounts?.id) return resolve()
      const script = document.createElement("script")
      script.src = "https://accounts.google.com/gsi/client"
      script.async = true
      script.defer = true
      script.onload = resolve
      document.head.appendChild(script)
    })
  }

  initializeOneTap() {
    window.google.accounts.id.initialize({
      client_id: this.clientIdValue,
      callback: this.handleCredential.bind(this),
      auto_select: true,
      cancel_on_tap_outside: true,
      context: "signin",
      use_fedcm_for_prompt: true
    })
    window.google.accounts.id.prompt()
  }

  handleCredential(response) {
    const csrfToken = document.querySelector(
      "meta[name='csrf-token']"
    )?.content

    fetch(this.loginPathValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ credential: response.credential })
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.ok) {
          // Signed in — drop any stale suppression so a later sign-out
          // re-enables One Tap.
          sessionStorage.removeItem(NO_ACCOUNT_KEY)
          window.location.replace(data.redirect || "/")
        } else if (data.error === "no_account") {
          // No account yet. Set the suppression flag FIRST so auto_select can't
          // re-fire One Tap → no_account → redirect in a loop on the bridge page
          // (or if the user bounces back without finishing OAuth). The flag is
          // cleared on sign-in (above) and while signed in (one-tap-reset
          // controller), so One Tap returns after a real sign-out. Then bridge
          // into the account-creating OAuth flow.
          sessionStorage.setItem(NO_ACCOUNT_KEY, "1")
          window.location.replace(data.redirect || "/create-account")
        }
      })
  }
}
