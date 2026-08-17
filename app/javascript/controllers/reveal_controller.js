// SPDX-License-Identifier: AGPL-3.0-or-later
import { Controller } from "@hotwired/stimulus"

// Reveal-on-scroll using IntersectionObserver — drops `opacity-0` and
// `translate-y-2` when the element first enters the viewport, giving a
// subtle fade-up entrance. One-shot (unobserve after first reveal).
//
// Honours `prefers-reduced-motion: reduce` — when the user opts out we
// reveal immediately on connect without any animation. The global
// transition-duration override in `application.css` already neuters the
// transition anyway, but skipping the observer entirely saves cycles.
//
// Usage:
//   <article data-controller="reveal"
//            class="opacity-0 translate-y-2 transition-all
//                   duration-[var(--motion-slow)] ease-[var(--ease-out-soft)]">
//     ...
//   </article>
//
// 🔴 [UI.4, 2026-08-17] ПЕРШ НІЖ ЗАДРОТУВАТИ — цей контролер несумісний із
// морфом, і несумісність НЕЗВОРОТНА. Сайтів у дереві сьогодні НУЛЬ (виміряно),
// тож дефект інертний; але `DashboardLayout` вмикає `turbo-refresh-method:
// morph` глобально, і на будь-якій дашборд-сторінці ланцюг такий:
//   1. вузол переживає морф (той самий елемент), тож Stimulus `connect()`
//      НЕ переграється;
//   2. idiomorph зводить `class` із серверною розміткою, а та несе `opacity-0`
//      → уже показаний елемент СТАЄ НЕВИДИМИМ знову;
//   3. `unobserve` нижче вже спрацював, тож ніхто його більше не покаже —
//      контент лишається невидимим до жорсткої навігації.
// Тобто «одноразовість» (крок 3) і є тим, що перетворює косметичний відкат на
// постійну втрату контенту. Лік, коли дійде до дроту, — на вибір: не робити
// `unobserve` (спостерігач лишається, показ ідемпотентний) АБО оголосити вузол
// непрозорим для морфу на осі атрибута (`turbo:before-morph-attribute` +
// `preventDefault()` на `class`, як `mobile_nav_controller` робить для `open`).
// ⛔ НЕ `data-turbo-permanent` — заборонений деревом із нульовим винятком.
// Механіка морфу й повний інвентар клієнтського стану → `04_04 §8`.
export default class extends Controller {
  static values = {
    threshold: { type: Number, default: 0.15 },
    rootMargin: { type: String, default: "0px 0px -10% 0px" }
  }

  connect() {
    if (this._prefersReducedMotion()) {
      this._reveal()
      return
    }

    if (typeof IntersectionObserver !== "function") {
      // Old browsers / SSR-snapshot — show immediately to avoid invisible content.
      this._reveal()
      return
    }

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this._reveal()
            this.observer.unobserve(entry.target)
          }
        })
      },
      { threshold: this.thresholdValue, rootMargin: this.rootMarginValue }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // ── private ──

  _reveal() {
    this.element.classList.remove("opacity-0", "translate-y-2", "translate-y-4")
  }

  _prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true
  }
}
