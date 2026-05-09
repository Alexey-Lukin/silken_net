import { Controller } from "@hotwired/stimulus"

// codex--fraction-picker — pick-confirmation guard + realm-tab UX hint.
//
// Contract (see app/views/components/codex/fractions/picker.rb):
//   data-controller="codex--fraction-picker"
//   targets: form (one per pickable node)
//
// Behaviour:
//   * Picking a fraction is a 7-day commitment. Before submission we
//     confirm the choice via `window.confirm` so a stray click doesn't
//     burn the cooldown.
//   * After confirmation the chosen card is "locked-in" visually
//     (opacity + cursor) while the request flies, so the user gets
//     immediate acknowledgement.
//   * Locked cards (the user's current fraction during cooldown) are
//     left alone — the disabled `<button>` already prevents submission.
//
// No-JS fallback: the form posts, the server enforces the cooldown
// authoritatively, and the user sees the result on the next page render.
export default class extends Controller {
  static targets = ["form"]

  connect() {
    if (!this.hasFormTarget) return
    this.boundSubmit = (e) => this.confirmPick(e)
    this.formTargets.forEach((form) => form.addEventListener("submit", this.boundSubmit))
  }

  disconnect() {
    if (this.boundSubmit && this.hasFormTarget) {
      this.formTargets.forEach((form) => form.removeEventListener("submit", this.boundSubmit))
    }
  }

  confirmPick(event) {
    const form = event.currentTarget
    if (form.dataset.confirmed === "true") return

    const slugInput = form.querySelector('input[name="fraction[node_slug]"]')
    const slug = slugInput ? slugInput.value : "this fraction"
    const ok = window.confirm(`Pick "${slug}"? Re-pick is locked for 7 days.`)
    if (!ok) {
      event.preventDefault()
      return
    }

    form.dataset.confirmed = "true"
    this.lockCard(form)
  }

  lockCard(form) {
    const card = form.closest("div")
    if (!card) return
    card.classList.add("opacity-60", "pointer-events-none")
    const button = form.querySelector("button")
    if (button) {
      button.disabled = true
      const span = button.querySelector("span") || button
      span.textContent = "Picking…"
    }
  }
}
