import { Controller } from "@hotwired/stimulus"

// Copies the text content of the `source` target to the clipboard. Used by the
// F3 one-time MCP-token reveal so the user can grab the secret before it is
// gone. Falls back to a hidden textarea + execCommand on older browsers.
export default class extends Controller {
  static targets = ["source"]

  async copy(event) {
    event.preventDefault()
    const text = this.sourceTarget.textContent.trim()

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.fallbackCopy(text)
    }

    this.flash(event.currentTarget)
  }

  fallbackCopy(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "absolute"
    area.style.left = "-9999px"
    document.body.appendChild(area)
    area.select()
    document.execCommand("copy")
    document.body.removeChild(area)
  }

  // Briefly swap the button label to confirm the copy.
  flash(button) {
    const label = button.querySelector("span") || button
    const original = label.textContent
    label.textContent = label.dataset.copiedLabel || "Copied"
    setTimeout(() => { label.textContent = original }, 1500)
  }
}
