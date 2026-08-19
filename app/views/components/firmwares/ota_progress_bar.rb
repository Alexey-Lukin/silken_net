# SPDX-License-Identifier: AGPL-3.0-or-later
module Firmwares
  # [I18N.2 · клас 1] Тут НЕМАЄ жодного `t()` — і це навмисно, а не недогляд.
  #
  # Компонент рендериться всередині `broadcast_*` (Sidekiq / coap-демон), де
  # `LocaleSettable` не відпрацьовує, тож будь-який `t()` тут віддав би локаль
  # ПРОДЮСЕРА всім глядачам (`04_04 §8.1а`). Раніше саме так і було: контролер
  # малював бар локаллю глядача, а перший же broadcast переписував його
  # `default_locale` і назад не вертав.
  #
  # Чому саме інваріантні токени, а не розщеплення на «сторінкова обгортка +
  # meter»: панель уже за дизайном — mono-readout, у якому `@status`
  # (TRANSMITTING/COMPLETE/FAILED/IDLE) рендериться СИРОЮ англійською. Слово
  # `COMPLETE` існувало тут одночасно в двох режимах — сире в статусі й
  # перекладене рядком нижче. Це була суперечність, не дизайн. А переклади,
  # які зникли, були транслітераціями того самого («ЧАНК», «OTA_ЛІНК»), тобто
  # в українській стало ЧЕСНІШЕ, не бідніше.
  class OtaProgressBar < ApplicationComponent
    def initialize(uid:, percent:, current:, total:, status:)
      @uid = uid
      @percent = percent
      @current = current
      @total = total
      @status = status
    end

    # 🔴 [UI.4] Дім target-id прогрес-бара: адресу називали рукою ТРИ сайти —
    # цей компонент і ДВА продюсери (push-воркер + живий poll-тракт FW.60).
    # ⚠️ `dom_id` тут непридатний у принципі: id ключується на `uid` шлюза, тобто
    # на НЕ-PK колонці, а `dom_id` вміє лише `param_key` + первинний ключ.
    def self.dom_id(uid) = "ota_progress_#{uid}"

    def view_template
      div(id: self.class.dom_id(@uid), class: "p-4 border border-emerald-900 bg-black font-mono") do
        div(class: "flex justify-between items-center mb-2") do
          span(class: "text-mini text-emerald-700 uppercase tracking-widest") { "OTA_LINK: #{@uid}" }
          span(class: tokens("text-mini", status_color)) { @status }
        end

        div(class: "w-full h-1 bg-emerald-950 rounded-full overflow-hidden") do
          div(class: "h-full bg-emerald-500 shadow-[0_0_10px_#10b981] transition-all duration-500", style: "width: #{@percent}%")
        end

        # total=0 — initial-render без кампанії (IDLE) або COMPLETE-сигнал:
        # чанк-лічильник не має що показувати.
        if @total.positive?
          div(class: "flex justify-between mt-2 text-micro text-gray-600") do
            span { "CHUNK: #{@current} / #{@total}" }
            span { "#{@percent}% COMPLETE" }
          end
        end
      end
    end

    private

    # [UI.3] Пульс знято з ДВОХ гілок: він стояв на самому слові статусу, тобто
    # робив нечитабельним рядок, який єдиний і повідомляє, чи прошивка впала.
    # Дискримінації він не ніс — усі чотири стани вже мають власний колір.
    def status_color
      case @status
      when "COMPLETE" then "text-emerald-400"
      when "FAILED"   then "text-red-500"
      when "IDLE"     then "text-gray-600"
      else "text-emerald-600"
      end
    end
  end
end
