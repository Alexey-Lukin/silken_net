// SPDX-License-Identifier: AGPL-3.0-or-later
import { Controller } from "@hotwired/stimulus"

// codex--reveal — pop-in animation for a Codex::Discoveries::Toast.
//
// Contract (see app/views/components/codex/discoveries/toast.rb):
//   data-controller="codex--reveal"
//   data-codex--reveal-trigger-value="<telemetry_observation|match_milestone|...>"
//
// Behaviour:
//   * On connect, the toast fades + slides in from the right.
//   * After AUTODISMISS_MS the toast fades out and removes itself from the DOM.
//   * Hovering the toast pauses the auto-dismiss timer (lets the user read).
//   * Respects `prefers-reduced-motion: reduce` — no transform, just opacity.
//
// No-JS fallback: the toast still appears (Turbo Stream broadcasts the
// markup); this controller only adds the cinematic affordance.
export default class extends Controller {
  static values = { trigger: String, autodismissMs: { type: Number, default: 8000 } }

  connect() {
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.style.opacity = "0"
    if (!this.reducedMotion) {
      this.element.style.transform = "translateX(16px)"
      this.element.style.transition = "opacity 320ms ease-out, transform 320ms ease-out"
    } else {
      this.element.style.transition = "opacity 200ms ease-out"
    }

    // Next frame so the initial state is committed before the transition runs.
    requestAnimationFrame(() => {
      this.element.style.opacity = "1"
      if (!this.reducedMotion) this.element.style.transform = "translateX(0)"
    })

    this.scheduleDismiss()
    this.boundPause = () => this.cancelDismiss()
    this.boundResume = () => this.scheduleDismiss()
    this.element.addEventListener("mouseenter", this.boundPause)
    this.element.addEventListener("mouseleave", this.boundResume)
    this.element.addEventListener("focusin",   this.boundPause)
    this.element.addEventListener("focusout",  this.boundResume)
  }

  disconnect() {
    this.cancelDismiss()
    if (this.boundPause) {
      this.element.removeEventListener("mouseenter", this.boundPause)
      this.element.removeEventListener("focusin",   this.boundPause)
    }
    if (this.boundResume) {
      this.element.removeEventListener("mouseleave", this.boundResume)
      this.element.removeEventListener("focusout",  this.boundResume)
    }
  }

  scheduleDismiss() {
    this.cancelDismiss()
    if (this.autodismissMsValue <= 0) return
    this.dismissTimer = setTimeout(() => this.dismiss(), this.autodismissMsValue)
  }

  cancelDismiss() {
    if (this.dismissTimer) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = null
    }
  }

  dismiss() {
    this.element.style.opacity = "0"
    if (!this.reducedMotion) this.element.style.transform = "translateX(16px)"
    setTimeout(() => this.element.remove(), this.reducedMotion ? 220 : 340)
  }
}
