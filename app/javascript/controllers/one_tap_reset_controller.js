import { Controller } from "@hotwired/stimulus"
import { NO_ACCOUNT_KEY } from "controllers/one_tap_constants"

// Clears the Google One Tap "no account" suppression flag while the user is
// signed in, so One Tap can prompt again after they sign out. Mounted (via
// ChromeHead#body_controllers) only on signed-in pages. (The flag is also
// cleared on a successful One Tap sign-in — see google_one_tap_controller.)
// Note: Google's FedCM cooldown is browser-enforced after a dismissal and
// cannot be reset from JS.
export default class extends Controller {
  connect() {
    sessionStorage.removeItem(NO_ACCOUNT_KEY)
  }
}
