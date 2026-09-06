# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт: кожне посилання з `target: "_blank"` у Phlex-дереві несе
# `rel: "noopener noreferrer"`.
#
# [SEC.36] Народився з проходу «що браузер отримує ПОНАД те, що сторінка
# показує» (2026-09-06). Зародок знайшовся випадково: у вʼю кластера центроїд
# друкується округленим до 4 знаків, а в `href` зовнішнього посилання йде повний
# float — тобто посилання везе БІЛЬШЕ, ніж бачить людина, і везе на чужий домен.
# Цілеспрямований прохід тією ж рамкою показав, що **пʼять із семи** зовнішніх
# `_blank`-посилань не несли `rel` взагалі, а ДВА несли (`blockchain_transactions/index`
# і `shared/ui/photo_card`) — тобто еталон у дереві стояв, і розходження було не
# рішенням, а недоглядом, повтореним пʼять разів.
#
# 🔑 Чому саме ГЕЙТ, а не разова правка: клас уже мав інстанси в пʼятьох файлах
# і жодного носія, тож наступне зовнішнє посилання народилось би без `rel` рівно
# так само. Правило без носія не стріляє — воно лише описує.
#
# 🔒 Оголошені стелі — зелений тут НЕ означає «зовнішні посилання безпечні»:
#   · Судиться НАЯВНІСТЬ атрибута, ніколи ПРИДАТНІСТЬ адресата. Посилання на
#     будь-який домен пройде; питання «чи можна туди відпускати субʼєкта і що
#     ми кладемо в query-string» — інша вісь, і вона в [SEC.36] залишена ⚖️
#     (три Google-Maps-посилання везуть сирі координати, класифіковані в
#     `04_01 §11` як PII через пере-ідентифікацію).
#   · Периметр — ЛИШЕ Phlex-вʼю (`app/views/**/*.rb`). Посилання, зібране в
#     JavaScript або повернуте як JSON-поле, сюди не входить за побудовою.
#   · Вікно пошуку атрибута — кілька рядків довкола `target:`, бо в Phlex
#     аргументи виклику `a(...)` розкидані по рядках. Виклик, що рознесе
#     `target:` і `rel:` далі, ніж на вікно, дасть ХИБНИЙ ПОЗИТИВ — і це
#     свідомий обмін: хибний позитив тут гучний і лікується одним рядком,
#     тоді як хибний негатив мовчить.
#   · `Referrer-Policy: strict-origin-when-cross-origin` (`config/application.rb`)
#     уже ріже шлях у Referer — але не `window.opener` і не те, що ми самі
#     поклали в URL. Дві різні осі; ця про першу.
RSpec.describe "external links carry rel=noopener", type: :model do
  it "every `target: \"_blank\"` in app/views declares rel with noopener" do
    offenders = []

    Dir.glob(Rails.root.join("app/views/**/*.rb")).sort.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, idx|
        next unless line.include?('target: "_blank"')

        window_lines = 4
        lo = [ idx - window_lines, 0 ].max
        hi = [ idx + window_lines, lines.size - 1 ].min
        window = lines[lo..hi].join
        next if window.include?("noopener")

        offenders << "#{path.sub("#{Rails.root}/", "")}:#{idx + 1}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      Зовнішнє посилання без `rel: "noopener noreferrer"` — #{offenders.size} шт:
        #{offenders.join("\n  ")}
      Форма — з еталона в дереві (`blockchain_transactions/index.rb`):
        a(href: ..., target: "_blank", rel: "noopener noreferrer", ...)
      Дім класу — `00_07` SEC.36.
    MSG
  end

  # Лантерна популяції: пін на порожній множині зелений завжди, тож множина
  # предметів мусить бути НЕПОРОЖНЬОЮ — інакше «всі несуть rel» правдиве й
  # порожнє водночас (00_05 §5).
  it "actually has subjects to judge" do
    count = Dir.glob(Rails.root.join("app/views/**/*.rb")).sum do |path|
      File.read(path).scan('target: "_blank"').size
    end

    expect(count).to be >= 5,
                     "лише #{count} `_blank`-посилань знайдено — предмет зник або периметр зламався, " \
                     "і зелений вище був би твердженням про ПРИЛАД, не про дерево"
  end
end
