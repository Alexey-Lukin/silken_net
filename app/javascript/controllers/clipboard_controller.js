import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { content: String }
  static targets = ["button"]

  copy() {
    navigator.clipboard.writeText(this.contentValue).then(() => {
      this.showFeedback()
    })
  }

  showFeedback() {
    const button = this.hasButtonTarget ? this.buttonTarget : this.element
    const original = button.innerHTML
    button.innerHTML = "✓"
    button.classList.add("text-emerald-300")

    setTimeout(() => {
      button.innerHTML = original
      button.classList.remove("text-emerald-300")
    }, 1500)
  }
}
