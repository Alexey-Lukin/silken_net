import { Controller } from "@hotwired/stimulus"

// codex--attune — optimistic UI for the attunement toggle.
//
// Contract (see app/views/components/codex/attunements/toggle.rb):
//   data-controller="codex--attune"
//   data-codex--attune-attuned-value="true|false"
//   data-codex--attune-node-id-value="<id>"
//   targets: count, form, button
//
// Behaviour:
//   * Clicking the button immediately:
//       - flips the attuned flag,
//       - bumps the visible count by ±1,
//       - swaps the button label and visual state.
//   * The form still submits normally (Turbo will rerender the canonical
//     state when the server responds), but the user sees the change instantly.
//   * On a request failure we revert. We listen for `turbo:submit-end` so we
//     don't reinvent fetch logic.
//
// No-JS fallback: the form posts/deletes normally; the count rerenders when
// `Codex::AttunementBroadcastWorker` publishes the Turbo Stream broadcast.
export default class extends Controller {
  static values  = { attuned: Boolean, nodeId: String }
  static targets = ["count", "form", "button"]

  connect() {
    if (!this.hasFormTarget) return
    this.boundSubmit = (e) => this.beforeSubmit(e)
    this.boundEnd    = (e) => this.afterSubmit(e)
    this.formTarget.addEventListener("submit",          this.boundSubmit)
    this.formTarget.addEventListener("turbo:submit-end", this.boundEnd)
  }

  disconnect() {
    if (!this.hasFormTarget) return
    if (this.boundSubmit) this.formTarget.removeEventListener("submit",          this.boundSubmit)
    if (this.boundEnd)    this.formTarget.removeEventListener("turbo:submit-end", this.boundEnd)
  }

  beforeSubmit(_event) {
    this.previousAttuned = this.attunedValue
    this.previousCount   = this.currentCount()

    const next = !this.attunedValue
    this.applyState(next, this.previousCount + (next ? 1 : -1))
  }

  afterSubmit(event) {
    const success = event?.detail?.success
    if (success === false) {
      // Revert — the server rejected our optimistic flip.
      this.applyState(this.previousAttuned, this.previousCount)
    }
  }

  applyState(attuned, count) {
    this.attunedValue = attuned
    if (this.hasCountTarget) this.countTarget.textContent = String(Math.max(0, count))

    if (this.hasButtonTarget) {
      const label = this.buttonTarget.querySelector("span")
      if (label) label.textContent = attuned ? "Attuned" : "Attune"
    }
    if (this.hasFormTarget) {
      this.formTarget.method = attuned ? "post" : "post" // _method override carries the verb
      const verb = this.formTarget.querySelector('input[name="_method"]')
      if (verb) verb.value = attuned ? "delete" : "post"
    }
  }

  currentCount() {
    if (!this.hasCountTarget) return 0
    const parsed = parseInt(this.countTarget.textContent, 10)
    return Number.isFinite(parsed) ? parsed : 0
  }
}
