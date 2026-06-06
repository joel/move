import { Controller } from "@hotwired/stimulus"

// Polls the capture session endpoint and swaps the panel HTML until no
// recognition run is still pending (the fetched fragment carries data-pending).
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 2500 } }
  static targets = ["frame"]

  connect() {
    if (this.#pending()) this.#start()
  }

  disconnect() {
    this.#stop()
  }

  #start() {
    this.timer = setInterval(() => this.#tick(), this.intervalValue)
  }

  #stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  async #tick() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/html" } })
      if (!response.ok) return
      this.frameTarget.innerHTML = await response.text()
      if (!this.#pending()) this.#stop()
    } catch (_error) {
      // Transient network error — keep polling on the next tick.
    }
  }

  #pending() {
    const node = this.frameTarget.querySelector("[data-pending]")
    return node ? parseInt(node.dataset.pending, 10) > 0 : false
  }
}
