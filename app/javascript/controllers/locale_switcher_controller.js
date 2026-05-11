import { Controller } from "@hotwired/stimulus"

// Positions a native HTML Popover next to its trigger button.
//
// The Popover API promotes `[popover]` elements to the top layer, which
// strips them out of the normal containing-block hierarchy — so a
// `position: relative` wrapper around the trigger has no effect, and the
// popover appears at the viewport's UA default (≈ centre).
//
// CSS Anchor Positioning (`anchor-name` / `position-anchor`) would solve
// this declaratively, but Firefox does not yet ship it (Baseline mid-2026).
// For now we listen to the `toggle` event the browser fires when the
// popover opens and pin it under the trigger's bottom-right corner using
// `position: fixed`. This keeps the JS-free popover semantics (light-
// dismiss, Escape, focus restore) and works in every popover-capable
// browser today.
//
// Markup contract:
//   <div data-controller="locale-switcher">
//     <button data-locale-switcher-target="trigger"
//             popovertarget="locale-switcher-popover">…</button>
//     <ul data-locale-switcher-target="popover"
//         id="locale-switcher-popover" popover>…</ul>
//   </div>
export default class extends Controller {
  static targets = ["trigger", "popover"]

  connect() {
    if (!this.hasPopoverTarget) return
    this.boundReposition = this._reposition.bind(this)
    this.popoverTarget.addEventListener("toggle", this.boundReposition)
    window.addEventListener("resize", this.boundReposition)
    window.addEventListener("scroll", this.boundReposition, true)
  }

  disconnect() {
    if (!this.boundReposition) return
    this.popoverTarget.removeEventListener("toggle", this.boundReposition)
    window.removeEventListener("resize", this.boundReposition)
    window.removeEventListener("scroll", this.boundReposition, true)
  }

  _reposition(event) {
    // Only run when the popover is open. The `toggle` event exposes
    // `newState`; resize/scroll listeners don't, so fall back to matching
    // on the `:popover-open` pseudo-state.
    const opening = event?.newState
      ? event.newState === "open"
      : this.popoverTarget.matches(":popover-open")
    if (!opening) return
    if (!this.hasTriggerTarget) return

    const rect = this.triggerTarget.getBoundingClientRect()
    const popover = this.popoverTarget

    // Right-align under the trigger, with a small 4px gap. Pin via `right`
    // so wider locale labels grow leftward instead of overflowing the
    // viewport's right edge.
    popover.style.position = "fixed"
    popover.style.margin = "0"
    popover.style.top = `${Math.round(rect.bottom + 4)}px`
    popover.style.right = `${Math.round(window.innerWidth - rect.right)}px`
    popover.style.left = "auto"
    popover.style.bottom = "auto"
  }
}
