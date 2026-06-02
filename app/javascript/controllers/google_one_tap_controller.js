import { Controller } from "@hotwired/stimulus"

const NO_ACCOUNT_KEY = "google_one_tap_no_account"

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
          window.location.replace(data.redirect || "/")
        } else if (data.error === "no_account") {
          // Suppress One Tap for the rest of this browser session
          // to avoid auto_select → no_account → redirect loops.
          sessionStorage.setItem(NO_ACCOUNT_KEY, "1")
          window.google.accounts.id.cancel()
        }
      })
  }
}
