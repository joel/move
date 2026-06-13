import { Controller } from "@hotwired/stimulus"

// Fills the L/W/H inputs from a tapped "reuse dimensions" chip (A2 Add Box).
// Weight is intentionally left alone — it varies per box. Phlex blocks inline
// on* handlers, so the click lives here, driven by data-action.
//   form_with(..., data: { controller: "dimension-presets" })
//   button(data: { action: "dimension-presets#apply", length:, width:, height: })
//   input(data: { dimension_presets_target: "length" })  # + width, height
export default class extends Controller {
  static targets = ["length", "width", "height", "chip"]

  apply(event) {
    const chip = event.currentTarget
    const { length, width, height } = chip.dataset
    this.lengthTarget.value = length
    this.widthTarget.value = width
    this.heightTarget.value = height

    // Reflect the active chip (drives the sage-fill CSS + a11y state).
    this.chipTargets.forEach((c) => c.setAttribute("aria-pressed", "false"))
    chip.setAttribute("aria-pressed", "true")
  }
}
