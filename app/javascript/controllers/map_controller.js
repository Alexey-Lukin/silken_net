// SPDX-License-Identifier: AGPL-3.0-or-later
import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static targets = ["node"]
  // [ARCH.84] Підпис стану «не виміряно» приходить із i18n через контейнер, а не
  // зашитим рядком: попап уже несе два англійські літерали (DID/Stress) — це борг
  // I18N.1, і збільшувати його новим станом не можна.
  static values = { unmeasuredLabel: String }

  // 🔴 [UI.11] Полотно оголошує себе НЕПРОЗОРИМ для морфу — і це лік КОРЕНЯ, а не
  // обхід. Виміряно браузером: під `turbo-refresh-method: morph` (глобальний
  // метатег `DashboardLayout`) морф лишає САМ вузол на місці, тож Stimulus не
  // кличе ні `disconnect()`, ні `connect()`, — а idiomorph зносить його дітей,
  // яких немає в серверній відповіді. Панелі Leaflet: **7 → 0**, `this.map`
  // лишається вказувати на мертвий DOM. Контроль тим самим приладом:
  // `method: "replace"` дає 7 → 7.
  //
  // Механіка скіпу (`turbo.js` 2.0.23): `beforeNodeMorphed` шле cancelable
  // `turbo:before-morph-element` (:2344), а `morphNode` на `false` виходить
  // ДО `morphAttributes`/`morphChildren` (:1893-1899) — тобто одного слухача на
  // корені досить, усе піддерево лишається недоторканим.
  //
  // ⛔ НЕ `data-turbo-permanent`, хоч він дав би той самий скіп (:2343): той
  // заборонений у цьому дереві з нульовим винятком (`no_turbo_permanent_spec`),
  // і заслужено — permanent діє ще й на Drive-візитах, тобто заморозив би
  // серверні дані. Подієвий скіп вужчий: він стосується ВИКЛЮЧНО морфу.
  //
  // ⚠️ Стеля названа: морф більше не приносить сюди свіжий серверний список
  // вузлів. Це не втрата — доставку тримає власний тракт (`Tree#broadcast_map_update`
  // → `map_node_{id}`), а морф-refresh на цій сторінці й сьогодні не стається
  // (єдина форма `/dashboard` — перемикач мови — несе `turbo_action: "advance"`).
  // ⊕ Дім класу: `04_04 §8`. Сусідній won't-do про цей самий хук
  // (`FlashMessages`) сюди НЕ переноситься: утриманий flash бреше, бо є
  // ТВЕРДЖЕННЯМ про минулу дію; утримане полотно — лише оболонка рендеру.
  connect() {
    this.skipMorph = (event) => event.preventDefault()
    this.element.addEventListener("turbo:before-morph-element", this.skipMorph)
    this.ensureMap()
  }

  // ⚠️ Stimulus піднімає targetObserver РАНІШЕ за controller.connect(), тож для
  // вузлів, уже присутніх у розмітці, `nodeTargetConnected` приходить ПЕРШИМ.
  // Доки ініціалізація жила просто в `connect()`, перше ж геолоковане дерево
  // ловило `this.markers` як undefined, виняток валив реєстрацію контролера
  // цілком — і мапа не будувалась саме тоді, коли їй було що показати.
  // Тому ініціалізація ідемпотентна й кличеться з обох входів. [TEST.7]
  ensureMap() {
    if (this.map) return

    // Ініціалізація карти. Координати за замовчуванням (Черкаси)
    this.map = L.map(this.element).setView([49.4444, 32.0598], 12)

    // [UI.1] Тайл їде за ТЕМОЮ ОС, не хардкодом: раніше dark_all стояв літералом,
    // і у світлій темі карта лишалась чорною плитою посеред світлої сторінки.
    // matchMedia тут — НЕ повернення JS-тумблера (⚖️ 08-08: тему обирає ОС, JS у
    // CSS-ланцюгу немає): Leaflet-тайли — растрові URL, media-query їх не
    // перемкне за побудовою, тож контролер читає ту САМУ ОС-перевагу, що й CSS.
    this.themeQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.tileLayer = L.tileLayer(this.tileUrl(this.themeQuery.matches), {
      // 🔴 Атрибуція — ВИМОГА ЛІЦЕНЗІЇ, не підпис. Дані OSM ліцензовані ODbL (§4.3
      // вимагає називати джерело в кожному похідному творі), тайли — за умовами CARTO.
      // Доти тут стояв самий лише наш рядок, який ЗАМІЩАВ обидва джерела; власний
      // підпис лишається, але ПОРУЧ, а не замість.
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
        '&copy; <a href="https://carto.com/attributions">CARTO</a> // Silken Net Geospatial Oracle',
      maxZoom: 19
    }).addTo(this.map)

    // Живе перемикання разом з ОС (слухач знімається в disconnect())
    this.onThemeChange = (event) => this.tileLayer.setUrl(this.tileUrl(event.matches))
    this.themeQuery.addEventListener("change", this.onThemeChange)

    this.markerLayer = L.layerGroup().addTo(this.map)
    this.markers = {} // Банк пам'яті: DID -> Marker

    // Захист від багів рендерингу в прихованих вкладках
    this.resizeTimeout = setTimeout(() => this.map.invalidateSize(), 200)
  }

  // Обидві теми — CARTO basemaps (та сама ліцензія/атрибуція, той самий CDN).
  tileUrl(dark) {
    const style = dark ? "dark_all" : "light_all"
    return `https://{s}.basemaps.cartocdn.com/${style}/{z}/{x}/{y}{r}.png`
  }

  disconnect() {
    // [UI.11] Слухач знімається явно: `disconnect()` тут викликається на Drive-візиті
    // (де вузол таки пересаджують), і лишений слухач пережив би власний контролер.
    if (this.skipMorph) {
      this.element.removeEventListener("turbo:before-morph-element", this.skipMorph)
      this.skipMorph = null
    }
    if (this.themeQuery && this.onThemeChange) {
      this.themeQuery.removeEventListener("change", this.onThemeChange)
      this.themeQuery = null
      this.onThemeChange = null
    }
    clearTimeout(this.resizeTimeout)
    if (this.map) {
      this.map.off()
      this.map.remove()
      this.map = null
    }
    this.markerLayer = null
    this.markers = {}
    // Turbo Drive Cache: видаляємо залишковий Leaflet DOM та CSS-класи,
    // щоб connect() міг ініціалізувати карту з чистого стану.
    this.element.replaceChildren()
    this.element.className = this.element.className.replace(/leaflet-\S+/g, '').trim()
  }

  // ⚡ [КЕНОЗИС]: Цей метод викликається АВТОМАТИЧНО, коли Turbo Stream
  // оновлює прихований <div> дерева в DOM. Ніякого ручного ActionCable!
  nodeTargetConnected(element) {
    this.ensureMap()
    this.updateMarker(element.dataset)
  }

  updateMarker(data) {
    const lat = parseFloat(data.lat)
    const lng = parseFloat(data.lng)
    const did = data.did

    // 🔴 [ARCH.84] «Не виміряно» — ОКРЕМИЙ канал, не четвертий колір. Колір тут
    // це рампа ЗДОРОВʼЯ (emerald→yellow→red), і додати до неї сірий означало б
    // сказати, що невиміряне дерево має якесь здоровʼя. Тому при відсутньому
    // вимірі рампа просто ЗНИКАЄ: маркер лишається порожнім кільцем без заливки
    // й БЕЗ `animate-ping` — пульс є заявою про живий сигнал, а ми його не маємо.
    // ⚠️ `data.stress` відсутній ≠ нуль: доти тут стояв `|| 0`, і нуль читався як
    // ідеальний гомеостаз (`map_node.rb` більше не друкує атрибут без виміру).
    const measured = data.stress !== undefined && data.stress !== ""
    const stress = measured ? parseFloat(data.stress) : null

    if (isNaN(lat) || isNaN(lng)) return

    // Емоційна палітра дерева
    let color = "#10b981" // Emerald (Гомеостаз)
    let shadow = "rgba(16, 185, 129, 0.5)"

    // [ARCH.99] Жовтий тримає ОДИН операнд — стрес. Другим стояв `charge < 30`,
    // а здорове дерево давало 18 %: умова була істинна завжди, тож смарагдовий
    // рядком вище не міг дожити до кінця функції для ЖОДНОГО вузла.
    // ⊕ `removed` лишається червоним і БЕЗ виміру: це факт статусу, не здоровʼя.
    if ((measured && stress > 0.8) || data.status === "removed") {
      color = "#ef4444" // Red (Термінальний стрес / Фрод)
      shadow = "rgba(239, 68, 68, 0.8)"
    } else if (measured && stress > 0.4) {
      color = "#eab308" // Yellow (Аномалія)
      shadow = "rgba(234, 179, 8, 0.6)"
    }

    const iconHtml = (!measured && data.status !== "removed")
      ? `
      <div class="relative w-4 h-4">
        <div class="relative w-4 h-4 rounded-full border-2 border-dashed border-gray-400 bg-transparent z-10"></div>
      </div>
    `
      : `
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
      this.markers[did].setPopupContent(this.popupTemplate(did, stress))
    } else {
      // Нове дерево — розміщуємо його
      const marker = L.marker([lat, lng], { icon: icon }).bindPopup(this.popupTemplate(did, stress))
      marker.addTo(this.markerLayer)
      this.markers[did] = marker

      // Авто-масштабування, щоб охопити весь сектор
      const group = new L.featureGroup(Object.values(this.markers))
      this.map.fitBounds(group.getBounds(), { padding: [40, 40], maxZoom: 16 })
    }
  }

  popupTemplate(did, stress) {
    const value = stress === null
      ? (this.unmeasuredLabelValue || "—")
      : `${(stress * 100).toFixed(1)}%`
    return `<div class="font-mono text-[10px] text-black"><b>DID: ${did}</b><br>Stress: ${value}</div>`
  }
}
