import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "iconLight", "iconDark", "switch", "knob"]

  connect() {
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.handleSystemChange = this.handleSystemChange.bind(this)
    this.applyTheme(localStorage.getItem("theme") || "dark")
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

    // The controller is mounted once on <body> but the toggle can be rendered
    // several times (root nav, Move sidebar, Move mobile top bar). Update every
    // target so the visible control always reflects the active theme.
    this.labelTargets.forEach((el) => {
      el.textContent = isDark ? "Light mode" : "Dark mode"
    })

    this.iconDarkTargets.forEach((el) => el.classList.toggle("hidden", !isDark))
    this.iconLightTargets.forEach((el) => el.classList.toggle("hidden", isDark))

    // F3 settings switch: reflect the active theme as the switch's on/off state.
    this.switchTargets.forEach((el) => {
      el.setAttribute("aria-checked", isDark ? "true" : "false")
    })

    this.knobTargets.forEach((el) => {
      el.classList.toggle("translate-x-6", isDark)
      el.classList.toggle("translate-x-1", !isDark)
    })
  }

  isDark() {
    return document.documentElement.classList.contains("dark")
  }
}
