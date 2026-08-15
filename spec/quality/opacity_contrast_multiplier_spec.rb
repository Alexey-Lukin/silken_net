# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ТРЕТЬОГО множника контрасту: безпрефіксна `opacity-N` на вузлі, який
# оголошує текст (`04_04 §3.5`, `00_07` UI.3).
#
# 🔴 ЧОМУ ЖОДЕН НАЯВНИЙ ПРИЛАД ЦЬОГО НЕ БАЧИВ, хоч один із них клас ЗНАВ.
# `design_token_existence_spec` судить ІСНУВАННЯ токена; браузерний збирач
# `contrast_audit` композитить стек ФОНІВ — а «opacity-група» стоїть у його
# кошику **UNMEASURABLE**, тобто він чесно відмовлявся міряти такий вузол. Саме
# ця чесність і ховала клас: «не можу виміряти» ніхто не читав як «тут може бути
# дефект», бо відмова не червоніє. Тут токен правильний і пара fg/bg правильна —
# губить їх третій множник, альфа переднього плану. Вимір (2026-08-16):
#
#   OracleVisions::ForecastCard   opacity-40  →  1.70 · 2.09 · 2.12 : 1  (поріг 3:1)
#   Alerts::Row (resolved)        opacity-40  →  16.10 → 2.46 : 1        (поріг 4.5:1)
#   StatusBadge cancelled/removed opacity-50  →   6.87 → 2.25 : 1        (поріг 4.5:1)
#   Shared::UI::EmptyState desc   opacity-70  →   7.41 → 3.54 : 1        (СВІТЛА тема)
#
# ⚠️ Останній — однотемний: у темній 6.69:1, тобто справний. Половина глядачів
# бачила справний екран, і це рівно та форма, заради якої друга палітра тримається
# як mutation-тест дизайн-системи (`04_04 §1`).
#
# 🔴 ЧОМУ ГЕЙТ НА ПРИСУТНІСТЬ, А НЕ НА ЗНАЧЕННЯ. Альфа, потрібна для порогу,
# залежить від КОЛЬОРУ: на `bg-zinc-950` це 0.692 для `text-red-500`, 0.549 для
# `text-emerald-500`, 0.544 для `text-gray-400` — а колір там деривується рантайм.
# Спільне безпечне значення (0.70) робить ефект невидимим, тобто прозорість
# несумісна з рантайм-кольором структурно, а не кількісно. І «на hover видно»
# ліком не є: на тачі hover'а немає, а WCAG 1.4.3 винятку «читабельно при
# наведенні» не має.
#
# ⚠️ СТЕЛЯ НАЗВАНА, і саме крізь неї прожив найдорожчий екземпляр. Гейт бачить
# вузол, який САМ оголошує текст (`text-…` у тому ж class-виразі). Прозорість на
# КОНТЕЙНЕРІ, чиї нащадки несуть текст, статично не видна взагалі — `Alerts::Row`
# глушила весь `<tr>` рядком `"bg-gaia-surface-sunken opacity-40"`, де жодного
# `text-` немає. Розширювати регекс на «будь-який вузол» відмовлено виміром: тоді
# під нього падають усі декоративні оверлеї, і гейт вироджується в реєстр.
# Клас (B) лишається за ревʼю — як голий `expectRevert` у Solidity (CLAUDE.md §8).
module OpacityContrastMultiplier
  SCANNED_GLOB = "app/views/**/*.rb"

  # Безпрефіксна утиліта: `opacity-40`, але НЕ `disabled:opacity-50` і не
  # `group-hover:opacity-100` — варіант описує ІНШИЙ стан, а не базовий рендер.
  # `opacity-0` теж поза класом: вузол не приглушений, його немає взагалі
  # (показ іде через парний `group-hover:opacity-100`), тож це питання
  # досяжності на тачі, а не контрасту — інша вісь, інший дім.
  OPACITY_PATTERN = /(?<![-\w:])opacity-(?!0\b|100\b)(\d+)/

  # Вузол оголошує текст: розмір або колір. Обидві половини несучі — `text-2xl`
  # без кольору успадковує його, а `text-red-500` без розміру теж друкує текст.
  TEXT_CLASS_PATTERN = /\btext-(?:xs|sm|base|lg|xl|\dxl|tiny|mini|micro|compact|[a-z]+-\d{2,3}|gaia-[\w-]+|status-[\w-]+)/

  # Машинні звільнення — кожне є СЕМАНТИЧНОЮ декларацією автора, не здогадкою
  # гейта про вигляд:
  #   `aria_hidden`         — вузол знято з дерева доступності (чиста декорація);
  #   `pointer-events-none` — шар не приймає взаємодії (фонова текстура/оверлей);
  #   `disabled`            — WCAG 1.4.3 явно звільняє неактивні компоненти.
  EXEMPTION_PATTERN = /aria_hidden|aria-hidden|pointer-events-none|disabled/

  # ⚠️ РЕЄСТР ПОРОЖНІЙ, І ЦЕ МЕТА. Усі чотири виміряні сайти виправлені, а не
  # внесені сюди: три зняттям прозорості, один — заміною на `line-through`, що
  # бере роль дискримінатора з сусіднього рядка тієї ж мапи. Гейт, який
  # народжується з винятками на власні знахідки, легалізує їх.
  DECLARED_EXCEPTIONS = {}.freeze

  module_function

  # 🔴 Коментарі відрізаються, і це не гігієна, а несуча умова. Кожен виправлений
  # сайт лишає по собі ПРОЗУ, що цитує зняту форму дослівно («доти тут стояла
  # `opacity-50`»), — тобто гейт, який читає коментарі, червоніє на власній
  # документації й знімається першим. Перший прогін це показав: три виправлені
  # файли лишились у множині хітів, а головний приклад був зелений лише тому,
  # що `opacity-40` і `text-2xl` випадково не збіглись в одному рядку прози.
  def code_only(line)
    return "" if line.lstrip.start_with?("#")

    line.split(/\s#\s/, 2).first.to_s
  end

  def dimmed_text_node?(line)
    code = code_only(line)
    code.match?(OPACITY_PATTERN) && code.match?(TEXT_CLASS_PATTERN) && !code.match?(EXEMPTION_PATTERN)
  end

  def scanned_files = Dir.glob(Rails.root.join(SCANNED_GLOB)).sort

  def files_with_opacity
    scanned_files.count { |p| File.readlines(p).any? { |l| code_only(l).match?(OPACITY_PATTERN) } }
  end

  def violations
    scanned_files.flat_map do |path|
      rel = path.sub("#{Rails.root}/", "")
      File.readlines(path).each_with_index.filter_map do |raw, idx|
        next unless dimmed_text_node?(raw)
        next if DECLARED_EXCEPTIONS[rel]&.fetch(:line) == idx + 1

        "#{rel}:#{idx + 1} → #{raw.strip[0, 110]}"
      end
    end
  end
end

RSpec.describe "opacity як прихований множник контрасту", type: :model do
  let(:gate) { OpacityContrastMultiplier }

  it "не глушить прозорістю вузол, що несе текст" do
    violations = gate.violations

    expect(violations).to be_empty, <<~MSG
      `opacity-N` на текстовому вузлі множить контраст, і жоден інший наш прилад
      цього не бачить — токен правильний, пара fg/bg правильна:

      #{violations.join("\n      ")}

      Лік: зняти прозорість і, якщо вона несла СИГНАЛ, узяти неколірний
      дискримінатор (`line-through`, окреме слово, інший фон). Якщо вузол
      декоративний — оголоси це семантично (`aria_hidden`), і гейт замовкне сам.
    MSG
  end

  it "бачить непорожню множину сканованих вузлів (liveness)" do
    # Без цього прикладу зламаний glob чи регекс зробили б гейт вакуумним:
    # «нуль порушень» означало б «нуль перевірених рядків». Пороги взято з
    # ВИМІРУ й опущено із запасом — пін на точне число зробив би гейт крихким
    # до кожного нового компонента, а ловить він зламаний glob (там нуль).
    expect(gate.scanned_files.size).to be > 50
    expect(gate.files_with_opacity).to be >= 5
  end

  it "пропускає ЗАКОННУ форму — декоративний вузол із прозорістю (GREEN-половина)" do
    # 🔴 Без цього прикладу гейт неможливо відрізнити від «забороняємо opacity
    # всюди»: RED-половина зелена й тоді, коли правило надто широке, а найдешевша
    # відповідь на надто широкий гейт — послабити його (§Guard-craft #52).
    # Взірець живий у дереві: іконка `Shared::UI::EmptyState` під `aria_hidden`.
    decorative = %q(p(class: "text-gaia-text-muted text-lg opacity-50", aria_hidden: "true") { @icon })

    expect(gate.dimmed_text_node?(decorative)).to be(false)
  end

  it "ловить базову форму, але не варіанти й не повну прозорість" do
    expect(gate.dimmed_text_node?(%(div(class: "font-mono text-2xl opacity-40")))).to be(true)

    # Варіант описує ІНШИЙ стан, а не базовий рендер — інакше два піни вище вакуумні.
    expect(gate.dimmed_text_node?(%(class: "text-sm disabled:opacity-50 cursor-not-allowed"))).to be(false)
    expect(gate.dimmed_text_node?(%(class: "text-sm opacity-0 group-hover:opacity-100"))).to be(false)
  end

  it "не читає власну документацію — цитата знятої форми в коментарі не є сайтом" do
    # Мутація-перевірено: без `code_only` рядок нижче червонить гейт, тобто
    # кожен пояснювальний коментар ставав би порушенням.
    expect(gate.dimmed_text_node?(%(    # доти тут стояло `text-2xl opacity-40` — знято))).to be(false)
  end

  it "оголошений виняток (якщо зʼявиться) несе підставу І умову відкликання — реєстр наразі порожній" do
    OpacityContrastMultiplier::DECLARED_EXCEPTIONS.each_value do |row|
      expect(row[:why]).to be_present
      expect(row[:back]).to be_present
    end
  end
end
