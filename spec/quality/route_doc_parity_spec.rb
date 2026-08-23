# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# 🔎 `04_03 §4` — ТАБЛИЦЯ ЕНДПОІНТІВ ЗВІРЯЄТЬСЯ З РОУТЕРОМ [DOC-T.87]
# =============================================================================
# `04_01`/`04_02` стереже `scripts/model_doc_sync.rb`, `04_04` —
# `scripts/component_doc_sync.rb`. Таблиця ендпоінтів `04_03 §4` була ЄДИНИМ
# механічним реєстром модуля 04 без сторожа, і `00_06 §3а` чесно лишав її в
# «ручному семантичному аудиті». Вона дрейфнула: `GET /wallets/:wallet_id/
# transactions/:id/status` жив у роутері, контролері, політиці, двох
# request-спеках і реєстрі контрасту — а в каноні його не було 17 діб при
# зеленому CI, у таблиці, яка зветься «Повна».
#
# 🔴 **Чому СПЕКА, а не скрипт у смузі `docs_check` — це присуд, не недогляд.**
# Обидва сіблінги — pure-Ruby парсери файлів, тому й живуть у джобі, що Rails
# НЕ піднімає. Тут джерелом істини мусить бути сам РОУТЕР: статичний парс
# `resources` був би реімплементацією Rails, тобто гейтом, який звіряє два наші
# власні тексти й доводить УЗГОДЖЕНІСТЬ, ніколи коректність. Роутер вимагає
# boot, отже дім — сюїта. ⛔ **Не додавати цьому гейту рядок у реєстр
# `00_06 §3`:** CHECK E реверс-перевіряє, що названа команда дослівно біжить у
# workflow, а сюїта їде одним `bin/rspec` — рядок став би вічно червоним.
# Сіблінг тієї ж форми й того ж предмета — `spec/security/
# path_literal_route_consistency_spec.rb` (throttle-шляхи проти роутера).
#
# ⚠️ **Оголошена стеля — гейт судить НАЯВНІСТЬ пари (метод, шлях), і більше
# нічого.** Колонки `Доступ`, `Controller#Action` і `Опис` він не звіряє: право
# доступу живе у `before_action`-ланцюгу та політиках, і зіставляти його з
# прозою означало б доводити узгодженість двох наших описів. Тобто рядок із
# ХИБНИМ `🔑 Auth` пройде цей гейт зеленим — це відомо й лишається на ручному
# семантичному аудиті (`00_06 §3а`).
#
# 🔒 Порожня множина обабіч дала б хибний зелений, тож популяція пінується
# окремим прикладом.
DOC_PATH = Rails.root.join("docs/04_03_REST_API_v1_Reference.md")

# Дієслова, які документ перелічує. `HEAD`/`OPTIONS` Rails генерує сам і
# реєстром вони не є.
HTTP_VERBS = %w[GET POST PATCH PUT DELETE].freeze

# Поза `api/v1/**` документ свідомо перелічує лише health-пару.
EXTRA_DOCUMENTED_PATHS = %w[/up /ready].freeze

RSpec.describe "04_03 §4 endpoint table matches the router" do # rubocop:disable RSpec/DescribeClass
  # --- бік РОУТЕРА -----------------------------------------------------------
  let(:router_entries) do
    raw = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller].to_s
      action     = route.defaults[:action].to_s
      path       = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      verb       = route.verb.to_s.presence || "GET"
      next unless HTTP_VERBS.include?(verb)

      in_scope = controller.start_with?("api/v1/") || EXTRA_DOCUMENTED_PATHS.include?(path)
      next unless in_scope

      { verb: verb, path: path, action: action }
    end

    reject_patch_mirrors(raw)
  end
  # --- бік ДОКУМЕНТА ---------------------------------------------------------
  # Скоуп навмисно звужений до секції §4: інакше таблиця з колонкою-дієсловом,
  # додана деінде в цьому доці, мовчки «задовольнила» б відсутній §4-рядок.
  let(:doc_section) do
    body = DOC_PATH.read
    start = body.index(/^## .*\b4\. /) || body.index("### 4.1")
    stop  = body.index(/^## /, start + 1)
    body[start...stop]
  end
  let(:doc_entries) do
    doc_section.lines.filter_map do |line|
      next unless line.start_with?("|")

      cells = line.split("|").map(&:strip)
      next unless cells.size > 4 && HTTP_VERBS.include?(cells[2])

      path = cells[3][/`([^`]+)`/, 1]
      next unless path

      { verb: cells[2], path: path }
    end
  end
  let(:router_keys) { router_entries.map { |e| [ e[:verb], e[:path] ] }.uniq }
  let(:doc_keys)    { doc_entries.map { |e| [ e[:verb], e[:path] ] }.uniq }

  # 🔴 Rails `resources` оголошує `#update` ДВІЧІ — `PATCH` і `PUT`. Другий не є
  # авторським ендпоінтом, і виключати його треба саме ПАРОЮ (той самий шлях І
  # той самий action), а не «всі PUT»: справжній авторський `PUT` тоді став би
  # невидимим для гейта. Виміряно 2026-08-23: без цього правила три з пʼяти
  # хітів були цим артефактом, тобто точність 40% замість 100%.
  def reject_patch_mirrors(entries)
    patched = entries.select { |e| e[:verb] == "PATCH" }.map { |e| [ e[:path], e[:action] ] }.to_set
    entries.reject { |e| e[:verb] == "PUT" && patched.include?([ e[:path], e[:action] ]) }
  end

  it "reads a non-empty registry from both sides" do
    expect(router_keys.size).to be >= 90
    expect(doc_keys.size).to be >= 90
  end

  it "documents every routable endpoint" do
    undocumented = (router_keys - doc_keys).sort_by(&:last)

    expect(undocumented).to be_empty, <<~MSG
      Маршрут існує, а рядка в `04_03 §4` немає:
      #{undocumented.map { |v, p| "  #{v.ljust(6)} #{p}" }.join("\n")}

      Таблиця §4 зветься «Повна» — і саме тому мовчазна дірка в ній дорожча за
      відсутній документ: читач вважає, що подивився. Додай рядок (§4.1 —
      браузерний контур, §4.2 — машинний; ARCH.77 вирішує, який саме).
    MSG
  end

  it "promises no endpoint the router cannot serve" do
    phantom = (doc_keys - router_keys).sort_by(&:last)

    expect(phantom).to be_empty, <<~MSG
      `04_03 §4` обіцяє маршрут, якого роутер не знає:
      #{phantom.map { |v, p| "  #{v.ljust(6)} #{p}" }.join("\n")}

      Або маршрут зняли й рядок осиротів, або в шляху друк. Обидва читаються
      клієнтом як робочий контракт.
    MSG
  end
end
