import { Controller } from "@hotwired/stimulus"

// Manages light / dark theme toggle.
// Reads preference from localStorage, falls back to OS media query.
// Toggles the `dark` class on <html>.
export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.applyTheme(this.currentTheme)
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.handleSystemChange)
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.handleSystemChange)
  }

  handleSystemChange = (event) => {
    // Only react if user has no explicit preference saved
    if (localStorage.getItem("theme")) return
    this.applyTheme(event.matches ? "dark" : "light")
  }

  toggle() {
    const next = this.currentTheme === "dark" ? "light" : "dark"
    localStorage.setItem("theme", next)
    this.applyTheme(next)
  }

  // ── private ──

  get currentTheme() {
    return (
      localStorage.getItem("theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
    )
  }

  applyTheme(theme) {
    const root = document.documentElement
    if (theme === "dark") {
      root.classList.add("dark")
    } else {
      root.classList.remove("dark")
    }
    this.updateIcon(theme)
  }

  updateIcon(theme) {
    if (!this.hasIconTarget) return
    // Sun for dark mode (click to switch to light), Moon for light mode
    this.iconTarget.innerHTML = theme === "dark" ? this.sunSVG : this.moonSVG
  }

  get sunSVG() {
    return `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.66 7.66l-.71-.71M4.05 4.05l-.71-.71M16 12a4 4 0 11-8 0 4 4 0 018 0z"/>
    </svg>`
  }

  get moonSVG() {
    return `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z"/>
    </svg>`
  }
}
