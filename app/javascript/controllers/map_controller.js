import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static targets = ["node"]

  connect() {
    // Ініціалізація карти. Координати за замовчуванням (Черкаси)
    this.map = L.map(this.element).setView([49.4444, 32.0598], 12)
    
    // Використовуємо Dark Matter стиль для кіберпанк-естетики
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: 'Silken Net // Geospatial Oracle',
      maxZoom: 19
    }).addTo(this.map)

    this.markerLayer = L.layerGroup().addTo(this.map)
    this.markers = {} // Банк пам'яті: DID -> Marker
    
    // Захист від багів рендерингу в прихованих вкладках
    setTimeout(() => this.map.invalidateSize(), 200)
  }

  // ⚡ [КЕНОЗИС]: Цей метод викликається АВТОМАТИЧНО, коли Turbo Stream
  // оновлює прихований <div> дерева в DOM. Ніякого ручного ActionCable!
  nodeTargetConnected(element) {
    this.updateMarker(element.dataset)
  }

  updateMarker(data) {
    const lat = parseFloat(data.lat)
    const lng = parseFloat(data.lng)
    const did = data.did
    const stress = parseFloat(data.stress || 0)
    const charge = parseInt(data.charge || 0)

    if (isNaN(lat) || isNaN(lng)) return

    // Емоційна палітра дерева
    let color = "#10b981" // Emerald (Гомеостаз)
    let shadow = "rgba(16, 185, 129, 0.5)"
    
    if (stress > 0.8 || data.status === "removed") {
      color = "#ef4444" // Red (Термінальний стрес / Фрод)
      shadow = "rgba(239, 68, 68, 0.8)"
    } else if (stress > 0.4 || charge < 30) {
      color = "#eab308" // Yellow (Аномалія / Низький заряд)
      shadow = "rgba(234, 179, 8, 0.6)"
    }

    // Створюємо пульсуючий HTML-маркер
    const iconHtml = `
      <div class="relative w-4 h-4">
        <div class="absolute inset-0 rounded-full animate-ping opacity-75" style="background-color: ${color};"></div>
        <div class="relative w-4 h-4 rounded-full border-2 border-black z-10 transition-colors duration-500" 
             style="background-color: ${color}; box-shadow: 0 0 15px ${shadow};"></div>
      </div>
    `
    const icon = L.divIcon({ html: iconHtml, className: 'custom-tree-marker', iconSize: [16, 16], iconAnchor: [8, 8] })

    if (this.markers[did]) {
      // Якщо дерево вже на карті — просто оновлюємо його колір/іконку
      this.markers[did].setIcon(icon)
      this.markers[did].setPopupContent(this.popupTemplate(did, stress, charge))
    } else {
      // Нове дерево — розміщуємо його
      const marker = L.marker([lat, lng], { icon: icon }).bindPopup(this.popupTemplate(did, stress, charge))
      marker.addTo(this.markerLayer)
      this.markers[did] = marker

      // Авто-масштабування, щоб охопити весь сектор
      const group = new L.featureGroup(Object.values(this.markers))
      this.map.fitBounds(group.getBounds(), { padding: [40, 40], maxZoom: 16 })
    }
  }

  popupTemplate(did, stress, charge) {
    return `<div class="font-mono text-[10px] text-black"><b>DID: ${did}</b><br>Stress: ${(stress * 100).toFixed(1)}%<br>Charge: ${charge}%</div>`
  }
}
