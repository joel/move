import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "iconLight", "iconDark"]

  connect() {
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.handleSystemChange = this.handleSystemChange.bind(this)
    this.applyTheme(localStorage.getItem("theme") || "system")
    this.mediaQuery.addEventListener("change", this.handleSystemChange)
  }

  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener("change", this.handleSystemChange)
    }
  }

  toggle() {
    const next = this.isDark() ? "light" : "dark"
    localStorage.setItem("theme", next)
    this.applyTheme(next)
  }

  handleSystemChange() {
    const stored = localStorage.getItem("theme")
    if (!stored || stored === "system") {
      this.applyTheme("system")
    }
  }

  applyTheme(mode) {
    const prefersDark = this.mediaQuery ? this.mediaQuery.matches : false
    const isDark = mode === "dark" || (mode === "system" && prefersDark)
    document.documentElement.classList.toggle("dark", isDark)

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = isDark ? "Light mode" : "Dark mode"
    }

    if (this.hasIconDarkTarget) {
      this.iconDarkTarget.classList.toggle("hidden", !isDark)
    }

    if (this.hasIconLightTarget) {
      this.iconLightTarget.classList.toggle("hidden", isDark)
    }
  }

  isDark() {
    return document.documentElement.classList.contains("dark")
  }
}
