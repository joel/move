import { Controller } from "@hotwired/stimulus"

// Fades the inline "Saved ✓" badge a moment after it appears (C3 auto-save). Each
// save replaces the badge via Turbo Stream, so connect() re-runs and a fresh,
// gently-disappearing confirmation is shown.
export default class extends Controller {
  static values = { delay: { type: Number, default: 1600 } }

  connect() {
    this.timeoutId = setTimeout(() => {
      this.element.classList.add("opacity-0")
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
  }
}
