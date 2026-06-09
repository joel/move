import { Controller } from "@hotwired/stimulus"

// Drives the F3 auto-confirm confidence slider: live-updates the displayed value
// while dragging (`display`) and submits the form on release (`submit`) so the
// new threshold persists through Moves::SetAutoConfirmThreshold. Submitting via
// requestSubmit keeps Turbo + CSRF intact (Phlex blocks inline on* handlers).
export default class extends Controller {
  static targets = ["input", "value"]

  display() {
    if (this.hasValueTarget) {
      this.valueTarget.textContent = Number(this.inputTarget.value).toFixed(2)
    }
  }

  submit() {
    this.element.requestSubmit()
  }
}
