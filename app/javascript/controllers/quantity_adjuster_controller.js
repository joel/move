import { Controller } from "@hotwired/stimulus"

// Wires Components::Ui::QuantityAdjuster: the +/- buttons step the hidden input
// (the submitted value) and the visible display, clamped at a minimum.
export default class extends Controller {
  static targets = ["input", "display"]
  static values = { min: { type: Number, default: 0 } }

  increase() {
    this.update(this.current + 1)
  }

  decrease() {
    this.update(this.current - 1)
  }

  get current() {
    return parseInt(this.inputTarget.value, 10) || 0
  }

  update(next) {
    const value = Math.max(this.minValue, next)
    this.inputTarget.value = value
    this.displayTarget.textContent = value
  }
}
