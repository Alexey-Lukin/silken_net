import { Controller } from "@hotwired/stimulus"

// Light progressive-enhancement on top of the no-JS <details>-driven
// LocaleSwitcher Phlex component:
//   * closes the dropdown on outside click
//   * closes on Escape
//   * submits the picked language via the underlying <form> (already
//     wired by the markup — we just close the menu after click)
//
// The actual locale persistence is handled server-side by
// LocalesController#update, so the controller can safely no-op if JS is
// disabled or fails to load.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("click", this.handleOutsideClick, true)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  // Called by submit button click — close the menu before navigation.
  submit() {
    this.close()
  }

  close() {
    if (this.element.tagName === "DETAILS") {
      this.element.removeAttribute("open")
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
