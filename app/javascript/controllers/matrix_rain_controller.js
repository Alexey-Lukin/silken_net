import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.canvas = this.element
    this.ctx = this.canvas.getContext("2d")
    
    // Алфавіт телеметрії
    this.chars = "0123456789ABCDEF".split("")
    this.fontSize = 12
    this.drops = []
    
    this.resize()
    window.addEventListener("resize", this.resize.bind(this))
    
    // Швидкість матриці
    this.interval = setInterval(this.draw.bind(this), 60)
  }

  disconnect() {
    clearInterval(this.interval)
    window.removeEventListener("resize", this.resize.bind(this))
  }

  resize() {
    this.canvas.width = this.element.parentElement.clientWidth
    this.canvas.height = this.element.parentElement.clientHeight
    const columns = Math.floor(this.canvas.width / this.fontSize)
    
    // Заповнюємо краплі, щоб вони починали падати випадково
    while(this.drops.length < columns) this.drops.push(Math.random() * -100)
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
