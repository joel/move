import { Controller } from "@hotwired/stimulus"

// Scrolls a freshly-rendered element into view and flashes a brief sage ring, so
// the result of a create/add action is visible without scrolling (AGENTS.md UX
// rule #1). The server renders the new row with `data-controller="highlight"`;
// Stimulus connects it the moment Turbo inserts it, so the cue fires once and
// then clears itself.
//
// Two ways in: a Turbo Stream insert (the scroll on connect is final), or a full
// Turbo visit after a redirect (#958 — a manual item add lands on the box page).
// On a visit, Turbo scrolls to the top AFTER rendering, undoing the connect-time
// scroll, so scroll again on that visit's `turbo:load` (fired after Turbo's own
// scroll). A stream-inserted element is disconnected before any later visit's
// `turbo:load`, and disconnect drops the listener, so it never re-scrolls.
//
// One-shot (#968): the element is marked `data-highlight-done` when the cue
// fires. Turbo's cache snapshot keeps that marker, so a Back/Forward restore (or
// a cached preview) reconnects the controller but skips the cue, which keeps
// the restored scroll and doesn't flash again.
const RING = ["ring-2", "ring-accent-sage", "ring-offset-2", "ring-offset-page"]

export default class extends Controller {
  static values = { duration: { type: Number, default: 1200 } }

  connect() {
    if ("highlightDone" in this.element.dataset) {
      // A snapshot taken mid-flash still carries the ring.
      this.element.classList.remove(...RING)
      return
    }
    this.element.dataset.highlightDone = ""
    this.scroll = () => this.element.scrollIntoView({ behavior: "smooth", block: "nearest" })
    this.scroll()
    document.addEventListener("turbo:load", this.scroll, { once: true })
    this.element.classList.add(...RING)
    this.timeoutId = setTimeout(() => this.element.classList.remove(...RING), this.durationValue)
  }

  disconnect() {
    if (this.scroll) document.removeEventListener("turbo:load", this.scroll)
    if (this.timeoutId) clearTimeout(this.timeoutId)
  }
}
