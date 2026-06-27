import { Controller } from "@hotwired/stimulus"

// Scrolls a freshly-streamed element into view and flashes a brief sage ring, so
// the result of a create/add action is visible without scrolling (AGENTS.md UX
// rule #1). The server renders the new row with `data-controller="highlight"`;
// Stimulus connects it the moment Turbo inserts it, so the cue fires once and
// then clears itself.
export default class extends Controller {
  static values = { duration: { type: Number, default: 1200 } }

  connect() {
    this.element.scrollIntoView({ behavior: "smooth", block: "nearest" })
    const ring = ["ring-2", "ring-accent-sage", "ring-offset-2", "ring-offset-page"]
    this.element.classList.add(...ring)
    this.timeoutId = setTimeout(() => this.element.classList.remove(...ring), this.durationValue)
  }

  disconnect() {
    if (this.timeoutId) clearTimeout(this.timeoutId)
  }
}
