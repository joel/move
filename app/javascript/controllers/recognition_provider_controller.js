import { Controller } from "@hotwired/stimulus"

// F3 / #185 / #187 — per-Move recognition provider + model selector. The
// segmented pills choose the active provider client-side: clicking one sets the
// hidden provider field, reveals the API-key field for a real provider (hidden
// for the keyless "fake"), shows whether that provider already has a stored key
// (masked hint), retargets the "Remove key" form, and swaps the model
// toggle/input to that provider's default + stored override. The model toggle is
// an inline edit: clicking it reveals a free-text input pre-filled with the shown
// model so the choice is never lost. The form persists via
// Moves::SetRecognitionProvider on submit (Phlex blocks inline on* handlers, so
// the behaviour lives here).
export default class extends Controller {
  static targets = [
    "pill", "providerInput", "keyWrap", "hint", "removeWrap", "removeForm",
    "modelWrap", "modelToggle", "modelToggleText", "modelInput"
  ]
  static values = {
    masks: Object, // { openai: "••••1234", anthropic: "", gemini: "" }
    models: Object // { openai: { default: "gpt-5-mini", override: "" }, ... }
  }

  select(event) {
    this.activate(event.params.provider)
  }

  // Reveal the editable model input, pre-filled with the currently shown model so
  // switching to edit never discards the choice; then focus it.
  editModel() {
    if (!this.hasModelInputTarget) return

    if (!this.modelInputTarget.value && this.hasModelToggleTextTarget) {
      this.modelInputTarget.value = this.modelToggleTextTarget.textContent.trim()
    }
    if (this.hasModelToggleTarget) this.modelToggleTarget.hidden = true
    this.modelInputTarget.hidden = false
    this.modelInputTarget.focus()
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

    this.syncModel(provider, real)
  }

  // Point the model toggle/input at the selected provider's own default + override,
  // and reset back to the display (button) mode.
  syncModel(provider, real) {
    if (this.hasModelWrapTarget) this.modelWrapTarget.hidden = !real
    if (!real) return

    const entry = (this.modelsValue && this.modelsValue[provider]) || {}
    const def = entry.default || ""
    const override = entry.override || ""

    if (this.hasModelToggleTextTarget) this.modelToggleTextTarget.textContent = override || def
    if (this.hasModelInputTarget) {
      this.modelInputTarget.value = override
      this.modelInputTarget.placeholder = def
      this.modelInputTarget.hidden = true
    }
    if (this.hasModelToggleTarget) this.modelToggleTarget.hidden = false
  }

  paint(pill, active) {
    pill.classList.toggle("bg-surface-container-high", active)
    pill.classList.toggle("text-text-warm", active)
    pill.classList.toggle("text-on-surface-variant", !active)
    if (active) pill.setAttribute("aria-current", "true")
    else pill.removeAttribute("aria-current")
  }
}
