import { Controller } from "@hotwired/stimulus"

// Box-form ✨ "Suggest with AI" (B1): fetches a proposed contents description and
// fills the textarea. The endpoint always returns a suggestion (AI when the Move
// has a provider configured, a deterministic category/label join otherwise), so
// the only failure to handle is the network/HTTP layer.
//
//   div(data: { controller: "ai-suggest", ai_suggest_url_value: suggestion_path })
//     textarea(data: { ai_suggest_target: "field" })
//     button(data: { action: "ai-suggest#suggest", ai_suggest_target: "button" })
//       span(data: { ai_suggest_target: "buttonLabel" }) // swapped to "Generating…"
export default class extends Controller {
  static values = { url: String }
  static targets = ["field", "button", "buttonLabel"]

  suggest() {
    if (this.loading) return
    this.#setLoading(true)

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, { headers: { Accept: "application/json", "X-CSRF-Token": token } })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      })
      .then((data) => {
        if (this.hasFieldTarget && data.description) this.fieldTarget.value = data.description
      })
      .catch(() => this.#flashError())
      .finally(() => this.#setLoading(false))
  }

  #setLoading(on) {
    this.loading = on
    if (this.hasButtonTarget) this.buttonTarget.disabled = on
    if (this.hasButtonLabelTarget) {
      if (on) {
        this.buttonLabelTarget.dataset.idle = this.buttonLabelTarget.textContent
        this.buttonLabelTarget.textContent = this.buttonLabelTarget.dataset.loading || "Generating…"
      } else if (this.buttonLabelTarget.dataset.idle) {
        this.buttonLabelTarget.textContent = this.buttonLabelTarget.dataset.idle
      }
    }
    if (on && this.hasFieldTarget) this.fieldTarget.classList.add("opacity-50")
    else if (this.hasFieldTarget) this.fieldTarget.classList.remove("opacity-50")
  }

  // Brief sage→error ring so a failed fetch isn't silently swallowed.
  #flashError() {
    if (!this.hasFieldTarget) return
    this.fieldTarget.classList.add("ring-2", "ring-error")
    setTimeout(() => this.fieldTarget.classList.remove("ring-2", "ring-error"), 2000)
  }
}
