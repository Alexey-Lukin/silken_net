# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ІСНУВАННЯ токена: кожен `<utility>-<gaia|status|token>-*` клас, ужитий у
# Phlex-дереві, мусить бути оголошений у `@theme` (`04_04 §3`).
#
# Народився з дефекту, що прожив непоміченим і був невидимий за побудовою:
# `text-gaia-primary-text` стояв на ДЕВ'ЯТИ сайтах у шести файлах, а
# `--color-gaia-primary-text` не існував ніде. Tailwind v4 на невідомий токен не
# лається — він просто НЕ ГЕНЕРУЄ клас, тож розмітка виглядає правильною, CSS
# мовчить, і колір тексту тихо успадковується від `<body>`. Наслідок був не
# косметичний: три кнопки Codex на `bg-gaia-primary` діставали успадкований
# `--gaia-text`, що в ТЕМНІЙ темі (єдиній, якою користуються) дає 1.98:1 при
# планці WCAG AA 4.5:1 — тобто нечитабельно. Спека самого компонента при цьому
# пінила `include("text-gaia-primary-text")` і була зелена: вона стверджувала
# наявність РЯДКА, а не існування токена (`04_06 §B.2` BP #14).
#
# 🔒 Стелі, названі чесно — зелений тут НЕ означає «кольори правильні»:
#   · Гейт судить ІСНУВАННЯ, ніколи ПРИДАТНІСТЬ. Оголошений токен із контрастом
#     1.1:1 пройде: контраст — окрема вісь (`00_07` UI.3), і вона потребує
#     фактичної пари fg/bg, яку статичний скан не бачить (фон часто приходить
#     від батьківського компонента або з `<body>` за три файли вгору).
#   · Джерелом істини свідомо взято `application.css`, а НЕ `app/assets/builds/`:
#     білд у `.gitignore`, тож у CI його може не бути, і гейт по ньому був би
#     зелений на порожній множині — той самий клас, який він мав би ловити.
#   · Скан покриває `app/views/**/*.rb`. Класи, зібрані з інтерполяції, з
#     констант або з БД (`Codex::Node#accent_token`), тут невидимі за побудовою.
#   · `@layer`-класи (`gaia-responsive-table`, `gaia-sticky-thead`) під регекс не
#     підпадають — вони не несуть utility-префікса, і це навмисно.
module DesignTokenGate
  CSS_PATH = Rails.root.join("app/assets/tailwind/application.css")

  # Утиліти, що приймають колірний токен. Список явний, а не «будь-яке слово
  # перед дефісом»: інакше гейт ловив би `gap-`, `p-`, `w-` і ставав шумом,
  # а шумний advisory — це вимкнений гейт (`ssot-maintenance` §Guard-craft).
  COLOUR_UTILITIES = %w[
    text bg border ring divide outline fill stroke accent caret
    from via to shadow decoration placeholder
  ].freeze

  # `/20` — Tailwind-суфікс прозорості; він НЕ частина імені токена, і зрізати
  # його обов'язково, інакше `bg-token-forest/20` читався б як окремий токен.
  TOKEN_RE = /
    (?<![-\w])
    (?:#{COLOUR_UTILITIES.join('|')})-
    ((?:gaia|status|token)-[a-z0-9-]+?)
    (?:\/\d{1,3})?
    (?![\w-])
  /x

  module_function

  def theme_block
    File.read(CSS_PATH)[/@theme\s*\{(.*?)^\}/m, 1]
  end

  def declared
    theme_block.to_s.scan(/--color-([a-z0-9-]+)\s*:/).flatten.to_set
  end

  def used
    Dir.glob(Rails.root.join("app/views/**/*.rb")).each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, acc|
      rel = Pathname(file).relative_path_from(Rails.root).to_s
      File.readlines(file).each_with_index do |line, idx|
        line.scan(TOKEN_RE).flatten.each { |token| acc[token] << "#{rel}:#{idx + 1}" }
      end
    end
  end
end

RSpec.describe "design tokens: every used token exists in @theme" do # rubocop:disable RSpec/DescribeClass
  let(:declared) { DesignTokenGate.declared }
  let(:used) { DesignTokenGate.used }

  # Ліхтар на власний вимір: гейт над порожньою множиною зелений назавжди, і
  # відрізнити «нічого не порушено» від «екстрактор осліп» можна лише так.
  it "extracts a non-trivial population from both sides" do
    expect(DesignTokenGate.theme_block).to be_present, "@theme block not found — the extractor is blind"
    expect(declared.size).to be >= 25
    expect(used.size).to be >= 25
  end

  it "declares every colour token the Phlex tree uses" do
    missing = used.reject { |token, _| declared.include?(token) }

    report = missing.map { |token, sites| "  #{token} — #{sites.size} site(s), e.g. #{sites.first}" }

    expect(missing).to be_empty, <<~MSG
      Phlex components use colour tokens that `@theme` never declares.
      Tailwind silently emits NO class for these, so the colour falls back to
      whatever the element inherits — the markup lies and the CSS stays quiet.

      Fix: declare `--color-<token>` in the `@theme` block of
      #{DesignTokenGate::CSS_PATH.relative_path_from(Rails.root)} (and give it a value in BOTH
      `:root` and the `prefers-color-scheme: dark` block), or drop the class from
      the component.

      #{report.join("\n")}
    MSG
  end
end
