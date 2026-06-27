import { Controller } from "@hotwired/stimulus"

// sessionStorage key holding the timestamp of the last `no_account` result, used
// to briefly suppress One Tap.
const NO_ACCOUNT_KEY = "google_one_tap_no_account"

// How long to suppress One Tap after a no_account result — just long enough to
// ride through the OAuth bridge redirect (/login?via=google → /auth/google)
// without the "Continue as <name>" card re-appearing on the bridge page. It then
// self-expires so One Tap re-prompts later (e.g. after a sign-out). We can't
// clear it on sign-out instead: sessionStorage is origin-scoped to the apex
// where One Tap runs, but sign-in/out happens on the org subdomain (a different
// origin), so a time-box is the only same-origin way to re-enable it.
const SUPPRESS_MS = 60_000

export default class extends Controller {
  static values = {
    clientId: String,
    loginPath: String
  }

  connect() {
    if (this.suppressed) return

    this.loadScript().then(() => this.initializeOneTap())
  }

  disconnect() {
    if (window.google?.accounts?.id) {
      window.google.accounts.id.cancel()
    }
  }

  // True while the recent no_account suppression window is still open; clears the
  // key once it has expired so the next visit can prompt again.
  get suppressed() {
    const since = Number(sessionStorage.getItem(NO_ACCOUNT_KEY))
    if (since && Date.now() - since < SUPPRESS_MS) return true

    sessionStorage.removeItem(NO_ACCOUNT_KEY)
    return false
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
      // Never auto-confirm a returning Google session: always show the
      // "Continue as <name>" card and wait for a deliberate tap. auto_select
      // signs the user in with no gesture, which on the post-deletion apex
      // landing silently re-creates the account the user just deleted.
      auto_select: false,
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
          sessionStorage.removeItem(NO_ACCOUNT_KEY)
          window.location.replace(data.redirect || "/")
        } else if (data.error === "no_account") {
          // Briefly suppress (so the One Tap card doesn't re-show on the bridge
          // page), then bridge into the account-creating OAuth flow. The window
          // self-expires so One Tap returns later — see SUPPRESS_MS.
          sessionStorage.setItem(NO_ACCOUNT_KEY, String(Date.now()))
          window.location.replace(data.redirect || "/create-account")
        }
      })
  }
}
