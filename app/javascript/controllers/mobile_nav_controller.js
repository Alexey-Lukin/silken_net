import { Controller } from "@hotwired/stimulus"

// Off-canvas Sidebar drawer for mobile / tablet-portrait viewports.
//
// Responsibilities:
//   * open()/close() the drawer with slide-in transform + backdrop fade
//   * sync aria-expanded on the trigger button
//   * Escape key + outside click + backdrop click close the drawer
//   * scroll-lock <body> while drawer is open (prevents background scroll)
//   * minimal focus management: move focus into the drawer on open, restore
//     to the trigger on close; trap Tab inside the drawer while it's open
//   * close on Turbo navigation so the next page doesn't inherit open state
//
// Targets:
//   - drawer        the slide-in panel (translate-x-full when closed)
//   - backdrop      the fixed overlay covering the page
//   - openButton    the hamburger trigger (kept in sync via aria-expanded)
//
// Usage (markup):
//   <div data-controller="mobile-nav">
//     <%# trigger lives in the top bar %>
//     <%= render Views::Shared::UI::MobileNavToggle.new %>
//
//     <div data-mobile-nav-target="backdrop"
//          class="fixed inset-0 bg-black/60 opacity-0 pointer-events-none
//                 transition-opacity duration-[var(--motion-base)] md:hidden z-40"
//          data-action="click->mobile-nav#close"></div>
//
//     <aside id="mobile-nav-drawer"
//            data-mobile-nav-target="drawer"
//            class="fixed inset-y-0 left-0 w-64 z-50 -translate-x-full
//                   transition-transform duration-[var(--motion-base)]
//                   ease-[var(--ease-out-soft)] md:hidden">
//       <%= render Navigation::Sidebar.new(...) %>
//     </aside>
//   </div>
export default class extends Controller {
  static targets = ["drawer", "backdrop", "openButton"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleTurboVisit = this.close.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("turbo:visit", this.handleTurboVisit)
    this._lastFocused = null
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("turbo:visit", this.handleTurboVisit)
    this._unlockScroll()
  }

  open(event) {
    if (event) event.preventDefault()
    if (this._isOpen()) return

    this._lastFocused = document.activeElement

    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.remove("-translate-x-full")
      this.drawerTarget.classList.add("translate-x-0")
      this.drawerTarget.setAttribute("aria-hidden", "false")
    }
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("opacity-0", "pointer-events-none")
      this.backdropTarget.classList.add("opacity-100")
    }
    if (this.hasOpenButtonTarget) {
      this.openButtonTarget.setAttribute("aria-expanded", "true")
    }

    this._lockScroll()

    // Move focus into the drawer (first focusable element).
    requestAnimationFrame(() => {
      const focusable = this._focusableElements()
      if (focusable.length) focusable[0].focus()
    })
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this._isOpen()) return

    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.add("-translate-x-full")
      this.drawerTarget.classList.remove("translate-x-0")
      this.drawerTarget.setAttribute("aria-hidden", "true")
    }
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.add("opacity-0", "pointer-events-none")
      this.backdropTarget.classList.remove("opacity-100")
    }
    if (this.hasOpenButtonTarget) {
      this.openButtonTarget.setAttribute("aria-expanded", "false")
    }

    this._unlockScroll()

    // Restore focus to whichever element opened the drawer.
    if (this._lastFocused && document.contains(this._lastFocused)) {
      this._lastFocused.focus()
    }
  }

  handleKeydown(event) {
    if (!this._isOpen()) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    // Manual focus-trap on Tab so keyboard users can't escape the drawer.
    if (event.key === "Tab") {
      const focusable = this._focusableElements()
      if (!focusable.length) return

      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      const active = document.activeElement

      if (event.shiftKey && active === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && active === last) {
        event.preventDefault()
        first.focus()
      }
    }
  }

  // ── Internals ────────────────────────────────────────────────────────────

  _isOpen() {
    return this.hasDrawerTarget && !this.drawerTarget.classList.contains("-translate-x-full")
  }

  _focusableElements() {
    if (!this.hasDrawerTarget) return []
    const selector = [
      "a[href]",
      "button:not([disabled])",
      "input:not([disabled])",
      "select:not([disabled])",
      "textarea:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")
    return Array.from(this.drawerTarget.querySelectorAll(selector))
      .filter((el) => el.offsetParent !== null)
  }

  _lockScroll() {
    this._previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
  }

  _unlockScroll() {
    document.body.style.overflow = this._previousOverflow || ""
  }
}
