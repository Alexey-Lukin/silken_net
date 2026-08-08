# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [UI.11] `data-turbo-permanent` не сміє стояти в цьому дереві — нуль вузлів,
# нуль винятків.
#
# Механізм, куплений тричі: Turbo при Drive-візиті ПЕРЕСАДЖУЄ permanent-вузол
# (Bardo) і викидає свіжу серверну розмітку, а morph такі вузли пропускає
# взагалі. Тож permanent над будь-яким рядком, що народив СЕРВЕР, заморожує цей
# рядок назавжди. Класом убито полотно Leaflet (`dashboard/map`), потім
# заморожено лічильник тривог і підсвітку меню в сайдбарі, і втретє —
# локалізований `aria-label`, тобто випадок, де «даних» на око не видно взагалі.
#
# 🔒 ЧОМУ ЗАБОРОНА, А НЕ ALLOWLIST. Множина дозволених id порожня, а реєстр
# винятків гниє тихо: запис переживає свою причину, і ніщо не червоніє. Заборона
# з нульовим винятком гнити не має чому. Якщо permanent колись справді
# знадобиться, повертати треба не рядок у списку, а ІМЕНОВАНИЙ виняток із
# доказом, що в піддереві немає жодного серверного рядка — включно з `aria-*`,
# `title`, `alt`, `value` і `data-label`.
#
# ⚠️ Носій переїхав сюди свідомо. Доти інваріант тримали два приклади на
# компоненті тумблера теми (компонентний — на відсутність атрибута, браузерний —
# на те, що ім'я їде за мовою). Тумблер знято разом із клієнтським вибором теми,
# тобто ОБИДВА носії зникали одним кроком, лишаючи інваріант без жодного
# сторожа. Тут він не залежить від існування конкретного компонента.
#
# ⚠️ Чесна стеля: гейт статичний і судить ДЖЕРЕЛО, а не DOM. Атрибут, зібраний
# у рантаймі з рядка (`"data-turbo-" + "permanent"`), пройде — це прийнято, бо
# такого патерну в дереві немає й він не є способом, яким цей клас повертається.
# Поведінкову половину тримає `spec/features/dashboard_browser_smoke_spec.rb`.
module TurboPermanentGate
  VIEWS_GLOB = Rails.root.join("app/views/**/*.rb")

  PERMANENT = /turbo_permanent|data-turbo-permanent/

  # Проза про атрибут легальна й потрібна — коментарі в дереві пояснюють, ЧОМУ
  # його зняли. Гейт, що не відрізняє код від прози, почервонів би на власній
  # документації й був би знятий першим, кому завадив.
  def self.code_line?(line)
    !line.strip.start_with?("#")
  end
end

RSpec.describe "[UI.11] У дереві немає жодного `data-turbo-permanent`" do # rubocop:disable RSpec/DescribeClass
  let(:scanned) { Dir[TurboPermanentGate::VIEWS_GLOB].sort }

  it "не знаходить атрибута в жодному Phlex-джерелі" do
    offenders = scanned.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, idx|
        next unless TurboPermanentGate.code_line?(line)
        next unless line.match?(TurboPermanentGate::PERMANENT)

        "#{Pathname(path).relative_path_from(Rails.root)}:#{idx + 1}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      `data-turbo-permanent` повернувся в дерево.

      Turbo пересаджує такий вузол при кожному Drive-візиті й викидає свіжу
      серверну розмітку, а morph пропускає його взагалі — тож будь-який рядок,
      який усередині нього народив СЕРВЕР, замерзає на значенні першого візиту.
      «Рядок» включає атрибути: `aria-label`, `title`, `alt`, `value`,
      `data-label`. Саме на атрибуті цей клас і ловився востаннє — видимого
      тексту у вузлі не було взагалі.

      #{offenders.join("\n")}
    MSG
  end

  # 🔴 Liveness: без цього «нуль порушень» означало б і «нуль перевірок» —
  # найтихіший спосіб, у який гейт стає декоративним (перейменували каталог,
  # звузили glob, і файл роками звітує зелене над порожньою множиною).
  it "справді сканує непорожню множину Phlex-джерел" do
    expect(scanned.size).to be > 50
    expect(scanned).to include(a_string_ending_with("app/views/layouts/dashboard_layout.rb"))
  end
end
