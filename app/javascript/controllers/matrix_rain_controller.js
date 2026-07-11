import { Controller } from "@hotwired/stimulus"

// Frame interval in ms (~16 fps is enough for decorative rain effect;
// saves CPU compared to 60 fps while keeping the visual smooth).
const FRAME_INTERVAL = 60

export default class extends Controller {
  connect() {
    // [UI.3] Декоративний дощ поважає prefers-reduced-motion: глобальний
    // CSS-гейт (application.css) глушить лише CSS-анімації, а не JS-canvas
    // rAF-цикл — гейтимось тут (дзеркало reveal_controller).
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true) return

    this.canvas = this.element
    this.ctx = this.canvas.getContext("2d")

    // Алфавіт телеметрії
    this.chars = "0123456789ABCDEF".split("")
    this.fontSize = 12
    this.drops = []
    this.lastFrame = 0
    this.running = true

    this.resize()
    this.handleResize = this.resize.bind(this)
    window.addEventListener("resize", this.handleResize)

    // requestAnimationFrame автоматично зупиняється, коли вкладка неактивна
    this.rafId = requestAnimationFrame(this.loop.bind(this))
  }

  disconnect() {
    this.running = false
    cancelAnimationFrame(this.rafId)
    window.removeEventListener("resize", this.handleResize)
  }

  resize() {
    this.canvas.width = this.element.parentElement.clientWidth
    this.canvas.height = this.element.parentElement.clientHeight
    const columns = Math.floor(this.canvas.width / this.fontSize)

    // Заповнюємо краплі, щоб вони починали падати випадково
    while (this.drops.length < columns) this.drops.push(Math.random() * -100)
  }

  loop(timestamp) {
    if (!this.running) return

    // Throttle до ~16 fps, щоб не навантажувати GPU без потреби
    if (timestamp - this.lastFrame >= FRAME_INTERVAL) {
      this.lastFrame = timestamp
      this.draw()
    }

    this.rafId = requestAnimationFrame(this.loop.bind(this))
  }

  draw() {
    // Напівпрозорий чорний фон створює хвіст за символами
    this.ctx.fillStyle = "rgba(0, 0, 0, 0.15)"
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)

    this.ctx.fillStyle = "#10b981" // Emerald-500
    this.ctx.font = `${this.fontSize}px monospace`

    for (let i = 0; i < this.drops.length; i++) {
      const char = this.chars[Math.floor(Math.random() * this.chars.length)]
      const x = i * this.fontSize
      const y = this.drops[i] * this.fontSize

      // Малюємо поточний символ
      this.ctx.fillText(char, x, y)

      // Скидання краплі вгору (97% ймовірність продовження падіння)
      if (y > this.canvas.height && Math.random() > 0.97) {
        this.drops[i] = 0
      }
      this.drops[i]++
    }
  }
}
