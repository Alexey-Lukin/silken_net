import { Controller } from "@hotwired/stimulus"

// Thin shim around the native <dialog> element for the mobile sidebar drawer.
//
// What the browser handles for free (no JS needed):
//   * focus-trap inside the dialog while it's open
//   * Escape-to-close (with `cancel`/`close` events)
//   * stacking on the top-layer above all other content
//   * `::backdrop` pseudo-element for the dim overlay
//   * inert page contents underneath
//   * focus restoration to the trigger when the dialog closes
//
// What we still need JS for:
//   * calling `dialog.showModal()` (the only way to open a modal <dialog>)
//   * closing on backdrop click (native dialogs don't do this by default)
//   * scroll-locking the body (Chromium does it automatically with showModal,
//     Safari does not — belt-and-braces lock keeps behaviour consistent)
//   * closing on Turbo navigations (so the next page doesn't inherit open state)
//   * keeping the trigger's aria-expanded in sync
//
// Targets:
//   - dialog        the native <dialog id="mobile-nav-drawer"> element
//
// Usage (markup):
//   <div data-controller="mobile-nav">
//     <button data-action="click->mobile-nav#open" aria-controls="mobile-nav-drawer">…</button>
//     <dialog id="mobile-nav-drawer" data-mobile-nav-target="dialog"
//             data-action="click->mobile-nav#backdropClick close->mobile-nav#onClose">
//       <%= render Navigation::Sidebar.new(...) %>
//     </dialog>
//   </div>
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.handleTurboVisit = this.close.bind(this)
    document.addEventListener("turbo:visit", this.handleTurboVisit)
  }

  disconnect() {
    document.removeEventListener("turbo:visit", this.handleTurboVisit)
    this._unlockScroll()
  }

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget || this.dialogTarget.open) return

    this.dialogTarget.showModal()
    this._syncTrigger(true)
    this._lockScroll()
  }

  close() {
    if (!this.hasDialogTarget || !this.dialogTarget.open) return
    this.dialogTarget.close()
  }

  // Wired via `close->mobile-nav#onClose`. Fires when the dialog closes for
  // any reason (Escape, programmatic .close(), backdrop-click handler).
  onClose() {
    this._syncTrigger(false)
    this._unlockScroll()
  }

  // Native <dialog> doesn't dismiss on backdrop click. We approximate it by
  // checking whether the click landed on the dialog element itself (the
  // backdrop bubbles up to the dialog node, but inner content does not).
  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // ── Internals ────────────────────────────────────────────────────────────

  _syncTrigger(open) {
    const trigger = this.element.querySelector("[aria-controls='mobile-nav-drawer']")
    if (trigger) trigger.setAttribute("aria-expanded", open ? "true" : "false")
  }

  _lockScroll() {
    this._previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
  }

  _unlockScroll() {
    document.body.style.overflow = this._previousOverflow || ""
  }
}
