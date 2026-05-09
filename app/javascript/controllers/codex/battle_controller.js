import { Controller } from "@hotwired/stimulus"

// codex--battle — keyboard shortcuts + skip-cooldown affordance for the
// Battle Arena (`Codex::Battle::Arena`).
//
// Contract (see app/views/components/codex/battle/arena.rb):
//   data-controller="codex--battle"
//   data-codex--battle-realm-value="<realm-slug>"
//   targets:
//     card  (one per side; data-codex--battle-side-value="left|right")
//     form  (one per card — submits the pick)
//     skip  (the skip form)
//
// Behaviour:
//   * `←` votes for the left card (submits its `form` target).
//   * `→` votes for the right card.
//   * `Space` skips the pair (submits the `skip` form).
//   * Visual focus ring on the keyed-towards card (`ring-2 ring-gaia-primary`)
//     when the user hovers a key, removed after 600ms.
//   * Keyboard listener is bound to `document` so the user doesn't have to
//     focus the arena first; we no-op when the focus is in a textarea or input.
//
// No-JS fallback: form `<button type="submit">` works for all three actions.
export default class extends Controller {
  static values  = { realm: String }
  static targets = ["card", "form", "skip"]

  connect() {
    this.boundKey = (e) => this.handleKey(e)
    document.addEventListener("keydown", this.boundKey)
  }

  disconnect() {
    if (this.boundKey) document.removeEventListener("keydown", this.boundKey)
    if (this.flashTimer) clearTimeout(this.flashTimer)
  }

  handleKey(event) {
    // Don't hijack typing.
    const tag = event.target?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || event.target?.isContentEditable) return
    // Don't hijack browser shortcuts.
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "ArrowLeft":  return this.pickSide("left", event)
      case "ArrowRight": return this.pickSide("right", event)
      case " ":
      case "Spacebar":   return this.skip(event)
    }
  }

  pickSide(side, event) {
    if (!this.hasCardTarget) return
    const card = this.cardTargets.find((c) => c.dataset["codex--battleSideValue"] === side)
    if (!card) return
    event.preventDefault()
    this.flash(card)
    const form = card.querySelector("form")
    if (form) this.requestSubmit(form)
  }

  skip(event) {
    if (!this.hasSkipTarget) return
    event.preventDefault()
    this.flash(this.skipTarget)
    const form = this.skipTarget.tagName === "FORM" ? this.skipTarget : this.skipTarget.querySelector("form")
    if (form) this.requestSubmit(form)
  }

  flash(node) {
    if (!node) return
    const ringClasses = ["ring-2", "ring-gaia-primary", "ring-offset-1"]
    node.classList.add(...ringClasses)
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => node.classList.remove(...ringClasses), 600)
  }

  requestSubmit(form) {
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }
}
