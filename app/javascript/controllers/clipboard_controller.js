import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { content: String }
  static targets = ["button"]

  copy() {
    navigator.clipboard.writeText(this.contentValue).then(() => {
      this.showFeedback()
    }).catch(() => {
      // Fallback: select text for manual copy when clipboard API is unavailable
      const temp = document.createElement("input")
      temp.value = this.contentValue
      document.body.appendChild(temp)
      temp.select()
      document.execCommand("copy")
      document.body.removeChild(temp)
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
    }, 2000)
  }
}
