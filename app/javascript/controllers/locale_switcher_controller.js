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
    this.boundOnToggle = this._onToggle.bind(this)
    this.popoverTarget.addEventListener("toggle", this.boundOnToggle)
  }

  disconnect() {
    if (!this.hasPopoverTarget || !this.boundOnToggle) return
    this.popoverTarget.removeEventListener("toggle", this.boundOnToggle)
    this._unbindWindowListeners()
  }

  // Toggle handler — only attach window listeners while the popover is
  // open. This avoids running resize/scroll callbacks on every page (the
  // LocaleSwitcher lives in the top bar and is mounted everywhere) when
  // the popover isn't even visible.
  _onToggle(event) {
    if (event.newState === "open") {
      this._reposition()
      this._bindWindowListeners()
    } else {
      this._unbindWindowListeners()
    }
  }

  _bindWindowListeners() {
    if (this._windowBound) return
    this._windowBound = true
    window.addEventListener("resize", this.boundReposition, { passive: true })
    window.addEventListener("scroll", this.boundReposition, { capture: true, passive: true })
  }

  _unbindWindowListeners() {
    if (!this._windowBound) return
    this._windowBound = false
    window.removeEventListener("resize", this.boundReposition)
    window.removeEventListener("scroll", this.boundReposition, { capture: true })
  }

  _reposition() {
    if (!this.hasTriggerTarget || !this.hasPopoverTarget) return
    if (!this.popoverTarget.matches(":popover-open")) return

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
