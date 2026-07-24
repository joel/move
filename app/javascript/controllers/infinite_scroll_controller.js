import { Controller } from "@hotwired/stimulus"

// Auto-submits the form it is attached to once it scrolls within reach of the
// viewport — the gallery pager's infinite-scroll trigger (#720). One-shot by
// design: the observer disconnects before submitting, so a jittery scroll
// can't double-fire, and the turbo_stream replace of the pager mounts a fresh
// instance that re-arms for the next page. If the request fails the observer
// is already gone and the form's own submit button remains the manual retry
// path; without IntersectionObserver support the button is the only path.
export default class extends Controller {
  static values = { margin: { type: String, default: "400px" } }

  connect() {
    if (!("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver(
      (entries) => this.#trigger(entries),
      { rootMargin: `0px 0px ${this.marginValue} 0px` }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
  }

  #trigger(entries) {
    // A delivery queued before disconnect() can land after teardown — a late
    // no-op, not a submit.
    if (!this.observer) return
    if (!entries.some((entry) => entry.isIntersecting)) return

    this.observer.disconnect()
    this.observer = null
    // Submit via the form's own button so its data-turbo-submits-with
    // "Loading…" swap applies to auto-fires, not just manual clicks.
    const button = this.element.querySelector("[type=submit]")
    if (button) {
      this.element.requestSubmit(button)
    } else {
      this.element.requestSubmit()
    }
  }
}
