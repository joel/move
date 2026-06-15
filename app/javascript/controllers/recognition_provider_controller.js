import { Controller } from "@hotwired/stimulus"

// F3 / #185 — per-Move recognition provider selector. The segmented pills choose
// the active provider client-side: clicking one sets the hidden provider field,
// reveals the API-key field for a real provider (hidden for the keyless "fake"),
// shows whether that provider already has a stored key (masked hint), and points
// the separate "Remove key" form at the selected provider. The form persists via
// Moves::SetRecognitionProvider on submit (Phlex blocks inline on* handlers, so
// the behaviour lives here).
export default class extends Controller {
  static targets = ["pill", "providerInput", "keyWrap", "hint", "removeWrap", "removeForm"]
  static values = { masks: Object } // { openai: "••••1234", anthropic: "", gemini: "" }

  select(event) {
    this.activate(event.params.provider)
  }

  activate(provider) {
    this.providerInputTarget.value = provider
    this.pillTargets.forEach((pill) => this.paint(pill, pill.dataset.provider === provider))

    const real = provider !== "fake"
    if (this.hasKeyWrapTarget) this.keyWrapTarget.hidden = !real

    const mask = (this.masksValue && this.masksValue[provider]) || ""
    if (this.hasHintTarget) this.hintTarget.textContent = mask
    if (this.hasRemoveWrapTarget) this.removeWrapTarget.hidden = !(real && mask)
    if (this.hasRemoveFormTarget && real) {
      this.removeFormTarget.action = this.removeFormTarget.dataset.urlTemplate.replace("PROVIDER", provider)
    }
  }

  paint(pill, active) {
    pill.classList.toggle("bg-surface-container-high", active)
    pill.classList.toggle("text-text-warm", active)
    pill.classList.toggle("text-on-surface-variant", !active)
    if (active) pill.setAttribute("aria-current", "true")
    else pill.removeAttribute("aria-current")
  }
}
