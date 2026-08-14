// SPDX-License-Identifier: AGPL-3.0-or-later
import { Controller } from "@hotwired/stimulus"

// Копіювання адреси в буфер обміну.
//
// 🔴 Декларативної форми в HTML/CSS не існує і навряд зʼявиться: запис у буфер —
// привілейована дія, дозволена браузером лише з обробника жесту користувача,
// інакше будь-яка сторінка тихо перезаписувала б буфер. Тому JS тут не наш
// вибір, а єдиний легальний шлях; `user-select: all` дав би не копіювання, а
// полегшене виділення — іншу фічу.
//
// Що знято 2026-08-14 і чому:
//
// 1. `document.execCommand("copy")` — задепрекейчений, і фолбек будував
//    тимчасовий <input>, чіпляв його до body, селектив і знімав. Він був ще й
//    НЕДОСЯЖНИЙ: `navigator.clipboard` не існує лише поза secure context, а всі
//    наші деплої на HTTPS (canopy теж матиме SSL), плюс localhost — secure.
//
// 2. 🔴 Головне — фолбек стояв у `.catch()` промісу, а `navigator.clipboard`
//    у небезпечному контексті `undefined`, тож `navigator.clipboard.writeText`
//    кидає TypeError СИНХРОННО, до появи промісу. `.catch` такого не ловить —
//    тобто гілка, написана рівно для цього випадку, не спрацювала б НІКОЛИ.
//    `async/await` + `try/catch` ловить обидва роди відмови одним блоком.
//
// 3. 🔴 `showFeedback()` викликався в catch-гілці БЕЗУМОВНО, а результат
//    `execCommand` (boolean) ігнорувався — кнопка показувала «✓» навіть коли
//    копіювання не сталося. Це самосвідчення: артефакт стверджував дію, якої
//    не перевіряв. Тепер успіх і відмова — різні стани.
//
// ⚠️ Текст оголошення приходить із розмітки (`*TextValue`), не з JS: локаль
// знає лише сервер. Порожнє значення = вимкнене оголошення, не англійський
// дефолт усередині коду.
export default class extends Controller {
  static values = { content: String, copiedText: String, failedText: String }
  static targets = ["icon", "check", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.contentValue)
      this.#report(this.copiedTextValue, true)
    } catch {
      this.#report(this.failedTextValue, false)
    }
  }

  // Іконку МІНЯЄМО, а не перезаписуємо `innerHTML` кнопки: та несе SVG, і
  // збереження/відновлення розмітки рядком губило б будь-яку вкладену зміну.
  #report(message, succeeded) {
    clearTimeout(this.resetTimeout)

    if (this.hasStatusTarget) this.statusTarget.textContent = message
    if (succeeded && this.hasIconTarget && this.hasCheckTarget) {
      this.iconTarget.classList.add("hidden")
      this.checkTarget.classList.remove("hidden")
    }
    this.element.classList.toggle("text-status-danger-accent", !succeeded)

    this.resetTimeout = setTimeout(() => this.#reset(), 2000)
  }

  #reset() {
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
    if (this.hasIconTarget && this.hasCheckTarget) {
      this.iconTarget.classList.remove("hidden")
      this.checkTarget.classList.add("hidden")
    }
    this.element.classList.remove("text-status-danger-accent")
  }

  disconnect() {
    clearTimeout(this.resetTimeout)
  }
}
