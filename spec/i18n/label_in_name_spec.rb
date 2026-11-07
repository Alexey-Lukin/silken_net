# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "prism"

# Гейт правила `04_04 §9` (рядок «`aria-label` на інтерактивних елементах») [UI.20]:
# контрол із ВИДИМИМ текстом іменує сам текст — `aria-label`, якщо він є, мусить
# дослівно МІСТИТИ видимий текст у КОЖНІЙ локалі (WCAG 2.5.3 Label in Name; axe
# `label-content-name-mismatch`). Інакше голосове керування «натисни <видиме>» не
# влучає, а скрінрідер чує фразу, якої на екрані немає.
#
# Чому статичний гейт поруч з axe-лінзою: лінза ганяє лише контури реєстру контрасту
# і в одній локалі, тож 2026-11-07 вона побачила два вузли там, де вимір по всіх
# `aria_label` × чотирьох локалях знайшов клас (фільтри · пагінація · «Відкрити» в
# рядках таблиць). Переклад розходиться окремо — його бачить лише вимір у кожній мові.
#
# Форма — авто-виявлення + іменований shrink-list (як `broadcast_payload_invariance`):
# кожен `a`/`button` з `aria_label:` і кожен `button_to` з `aria: { label: }` у
# `app/views/**` потрапляє під перевірку сам; форма, яку гейт не вміє судити, червоніє,
# доки її не назвуть в UNJUDGED з причиною, а мертвий виняток червоніє теж.
#
# Порівняння — дзеркало axe 4.14 (`label-content-name-mismatch`, виміряно в
# `axe-core-api` 4.14.0): NFKD, зняти `(…)`, усе, що не літера й не цифра, — у пробіл,
# далі СЛОВА; видимий текст мусить стояти в мітці СУЦІЛЬНОЮ послідовністю слів (підрядок
# не рахується: «РЕДАГ» у «Редагувати…» — провал), а текстові вузли сусідніх елементів
# склеюються БЕЗ пробілу, як у axe («Контекст»+«Acme» = одне слово). Видимий текст з
# одного символу axe вважає «неповним» — тут теж пропуск, не провал.
#
# 🔒 Стеля, названа чесно:
#   · СТАТИЧНИЙ розбір (Prism). Видимий текст читається лише з форм: `t("…")`, рядковий
#     літерал, `plain`, вкладені елементи (без класу-токена `sr-only`; `aria-hidden` для
#     axe видимий, тож лишається), `svg` і метод того ж файлу, чиє тіло — лише `svg`
#     (іконка), і вираз, ТОТОЖНИЙ за джерелом аргументу інтерполяції мітки. Решта —
#     UNJUDGED. У `button_to` без блоку видимий текст — перший позиційний аргумент.
#   · Хелпери `link_to`/`tag.*`, сплати `**attrs` і віджети з `role:` поза розбором (на
#     2026-11-07 у `app/views` таких із міткою немає — перевірено адверсарем).
#   · Орієнтири (`nav`) і `role="status"`/`"img"` — поза правилом axe, тут не судяться.
#   · `Intl.Segmenter` axe замінено поділом за пробілами — для кирилиці й латиниці
#     межі слів ті самі; арбітр лишається axe-лінза (`spec/features/axe_audit_spec.rb`).
#   · CSS-видимість (`hidden lg:block`) не розрізняє: схований на вузькому екрані текст
#     рахується видимим.
module LabelInNameScan
  WIDGETS = %i[a button].freeze
  SILENT_ELEMENTS = %i[svg].freeze

  # Форми, які гейт не вміє судити, — кожна з причиною. Ключ: «шлях::джерело мітки».
  UNJUDGED = {
    %(app/views/shared/ui/photo_card.rb::(t("ui.photo_card.view_photo", filename: @photo.filename) if @photo.representable?)) =>
      "мітка лише на гілці-зображенні (тексту там немає, `alt` = імʼя файлу); fallback з іменем і розміром іменує власний текст"
  }.freeze

  Site = Struct.new(:path, :line, :aria_key, :aria_kwargs, :visible, :reason, keyword_init: true) do
    def key = "#{path}::#{aria_key}"
  end

  module_function

  def scan(root = Rails.root.to_s)
    loader = Rails.autoloaders.main
    Dir[File.join(root, "app/views/**/*.rb")].sort.flat_map do |path|
      src = File.read(path)
      next [] unless src.include?("aria_label") || src.include?("aria:")

      tree = Prism.parse(src).value
      scope = loader.cpath_expected_at(path)&.underscore&.tr("/", ".")
      rel = path.delete_prefix("#{root}/")
      silent = silent_helpers(tree)
      widgets(tree).map { |call| site_for(call, rel, scope, silent) }
    end
  end

  # Методи файлу, тіло яких — лише `svg(…)`: іконка, видимого тексту не дає.
  def silent_helpers(node, acc = Set.new)
    return acc unless node

    if node.is_a?(Prism::DefNode) && node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1
      only = node.body.body.first
      acc << node.name if only.is_a?(Prism::CallNode) && only.receiver.nil? && SILENT_ELEMENTS.include?(only.name)
    end
    node.compact_child_nodes.each { |child| silent_helpers(child, acc) }
    acc
  end

  def widgets(node, acc = [])
    return acc unless node

    acc << node if node.is_a?(Prism::CallNode) && node.receiver.nil? && label_node(node)
    node.compact_child_nodes.each { |child| widgets(child, acc) }
    acc
  end

  # Мітка віджета: `aria_label:` на `a`/`button` або `aria: { label: }` на `button_to`.
  def label_node(call)
    kw = kwargs_of(call)
    return kw[:aria_label] if WIDGETS.include?(call.name)
    return unless call.name == :button_to && kw[:aria].is_a?(Prism::HashNode)

    kw[:aria].elements.find { |el| el.is_a?(Prism::AssocNode) && el.key.is_a?(Prism::SymbolNode) && el.key.unescaped == "label" }&.value
  end

  def kwargs_of(call)
    hash = (call.arguments&.arguments || []).find { |arg| arg.is_a?(Prism::KeywordHashNode) }
    return {} unless hash

    hash.elements.each_with_object({}) do |el, out|
      out[el.key.unescaped.to_sym] = el.value if el.is_a?(Prism::AssocNode) && el.key.is_a?(Prism::SymbolNode)
    end
  end

  def t_key(node)
    return unless node.is_a?(Prism::CallNode) && node.receiver.nil? && %i[t translate].include?(node.name)

    first = node.arguments&.arguments&.first
    first.unescaped if first.is_a?(Prism::StringNode)
  end

  def resolve(key, scope) = key.start_with?(".") ? "#{scope}#{key}" : key

  # Видимий вміст: блок; у `button_to` без блоку — перший позиційний аргумент.
  def visible_node(call)
    return call.block.body if call.block.is_a?(Prism::BlockNode)
    return unless call.name == :button_to

    (call.arguments&.arguments || []).first
  end

  def site_for(call, path, scope, silent)
    aria = label_node(call)
    line = call.location.start_line
    akey = t_key(aria)
    return Site.new(path:, line:, aria_key: aria.slice, reason: "мітка — не `t(\"…\")`") unless akey

    akw = kwargs_of(aria).except(:default, :scope).transform_values(&:slice)
    parts, why = collect(visible_node(call), akw, silent)
    parts = parts&.map { |kind, a, b| kind == :t ? [ :t, resolve(a, scope), b ] : [ kind, a, b ] }
    Site.new(path:, line:, aria_key: resolve(akey, scope), aria_kwargs: akw, visible: parts, reason: why)
  end

  # → [parts, nil] або [nil, причина]; part = [:t, key, kwargs] | [:lit, text] | [:tok, kwarg_name]
  def collect(node, akw, silent)
    case node
    when nil then [ [], nil ]
    when Prism::StatementsNode
      node.body.each_with_object([ [], nil ]) do |child, acc|
        parts, why = collect(child, akw, silent)
        return [ nil, why ] if why

        acc[0].concat(parts)
      end
    when Prism::StringNode then [ [ [ :lit, node.unescaped ] ], nil ]
    when Prism::CallNode then collect_call(node, akw, silent)
    else tied(node, akw)
    end
  end

  def collect_call(node, akw, silent)
    if (key = t_key(node))
      kw = kwargs_of(node)
      return [ nil, "видимий `t(…)` із `count:`" ] if kw.key?(:count)

      return [ [ [ :t, key, kw.transform_values(&:slice) ] ], nil ]
    end
    bare = node.receiver.nil?
    return collect(node.arguments&.arguments&.first, akw, silent) if bare && node.name == :plain
    return [ [], nil ] if bare && SILENT_ELEMENTS.include?(node.name)
    return [ [], nil ] if bare && node.arguments.nil? && node.block.nil? && silent.include?(node.name)

    if bare && node.block.is_a?(Prism::BlockNode) && node.name != :render
      # `sr-only` — лише ЦІЛИЙ токен класу (`md:not-sr-only` видимий); `aria-hidden`
      # текст для axe лишається видимим, тож його не викидаємо.
      css = kwargs_of(node)[:class]
      return [ [], nil ] if css.is_a?(Prism::StringNode) && css.unescaped.split.include?("sr-only")

      return collect(node.block.body, akw, silent)
    end
    tied(node, akw)
  end

  # Вираз, що стоїть у видимому тексті й ТОЙ САМИЙ, що аргумент інтерполяції мітки.
  def tied(node, akw)
    name = akw.key(node.slice)
    name ? [ [ [ :tok, name ] ], nil ] : [ nil, "видимий вираз `#{node.slice.lines.first.strip}` не повʼязаний з інтерполяцією мітки" ]
  end

  # Дзеркало axe 4.14 (`label-content-name-mismatch`): NFKD → зняти `(…)` → усе, що не
  # літера й не цифра, у пробіл → слова; видиме мусить стояти СУЦІЛЬНОЮ послідовністю слів.
  def words(text)
    s = text.to_s.unicode_normalize(:nfkd)
    loop { t = s.gsub(/\([^()]*\)/, ""); break if t == s; s = t }
    s.downcase.gsub(/[^\p{L}\p{N}]/, " ").split
  end

  # Розбіжності сайту по всіх локалях (порожньо — сайт чистий). Видимі частини axe
  # склеює БЕЗ пробілу (текстові вузли сусідніх елементів), тож і тут — `join("")`.
  def mismatches(site, locales)
    tokens = site.aria_kwargs.keys.each_with_index.to_h { |name, i| [ name, "qz#{i}x" ] }
    by_src = site.aria_kwargs.to_h { |name, src| [ src, tokens[name] ] }
    locales.filter_map do |loc|
      aria = I18n.t(site.aria_key, locale: loc, raise: true, **tokens)
      visible = site.visible.map do |kind, a, b|
        case kind
        when :lit then a
        when :tok then tokens[a]
        when :t then I18n.t(a, locale: loc, raise: true, **b.to_h { |k, src| [ k, by_src.fetch(src, "qv#{k}x") ] })
        end
      end.join
      vis = words(visible)
      next if vis.join.length <= 1 # axe: не людськочитане → «неповно», не провал
      next if words(aria).each_cons(vis.size).include?(vis)

      "#{site.path}:#{site.line} [#{loc}] #{site.aria_key}: видимий «#{visible}» ⊄ aria-label «#{aria}»"
    end
  end
end

RSpec.describe "Label in Name — aria-label містить видимий текст у кожній локалі (WCAG 2.5.3) [UI.20]" do # rubocop:disable RSpec/DescribeClass
  let(:sites)  { LabelInNameScan.scan }
  let(:judged) { sites.reject(&:reason) }

  it "сканує живу популяцію — ліхтар: нуль судимих сайтів означав би сліпий розбір, а не чисте дерево" do
    expect(judged.size).to be >= 5
  end

  it "жоден `aria-label` на контролі з видимим текстом не губить цей текст у жодній локалі" do
    found = judged.flat_map { |site| LabelInNameScan.mismatches(site, I18n.available_locales) }
    expect(found).to be_empty, "WCAG 2.5.3 — імʼя дає видимий текст (`04_04 §9`):\n#{found.join("\n")}"
  end

  it "кожна форма, яку гейт не вміє судити, названа в UNJUDGED, і кожен виняток ще живий" do
    live = sites.select(&:reason).to_h { |site| [ site.key, site.reason ] }
    expect(live.keys - LabelInNameScan::UNJUDGED.keys).to be_empty,
      "нова несудима форма — прочитай і внеси з причиною:\n#{(live.keys - LabelInNameScan::UNJUDGED.keys).map { |k| "#{k} — #{live[k]}" }.join("\n")}"
    expect(LabelInNameScan::UNJUDGED.keys - live.keys).to be_empty,
      "мертвий виняток — зніми:\n#{(LabelInNameScan::UNJUDGED.keys - live.keys).join("\n")}"
  end
end
