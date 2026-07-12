import { Controller } from "@hotwired/stimulus"

// Resets a form after a *successful* Turbo submission and refocuses its first
// text field, so an inline "add another" row is immediately ready for the next
// entry. Turbo only auto-resets forms that end in a redirect; a form that
// responds with a Turbo Stream (the no-reload path) keeps its typed value, which
// would re-submit the same record. A failed submission (non-2xx) is left intact
// so the user doesn't lose what they typed.
export default class extends Controller {
  reset(event) {
    if (event.detail && event.detail.success === false) return
    this.element.reset()
    this.element.querySelector("input[type=text], input[type=email]")?.focus()
  }
}
