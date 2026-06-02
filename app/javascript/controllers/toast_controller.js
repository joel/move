import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 4500 }
  }

  connect() {
    this.timeoutId = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  disconnect() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
  }

  dismiss() {
    this.element.classList.add("-translate-y-2", "opacity-0")
    this.element.addEventListener("transitionend", () => {
      this.element.remove()
    }, { once: true })
  }
}
