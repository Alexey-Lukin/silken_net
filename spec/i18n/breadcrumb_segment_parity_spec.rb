# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт осі «маршрути → базова локаль» для хлібних крихт `DashboardLayout`.
#
# Крихта друкує СЕГМЕНТ URL, тож джерелом істини для множини є
# `Rails.application.routes`, а не модель (`04_04 §12.14`) — і саме тому цю вісь
# не бачить ЖОДЕН наявний гейт: `i18n-tasks missing` звіряє локаль з локаллю, а
# `enum_label_parity_spec` ранжується по enum'ах моделей і breadcrumb-сегменти
# зі свого периметра виключає явно.
#
# Дефект, який гейт ловить, МОВЧАЗНИЙ за побудовою: дім мітки fail-open
# (`default: value.humanize`), тож новий ресурс рендериться англійським словом у
# всіх чотирьох локалях і нічого не червоніє. Рівно так «Account security» /
# «Trees» простояли на КОЖНІЙ сторінці дашборда.
#
# 🔑 Популяція деривується ДВОМА структурними осями, і рукописних винятків тут
# НЕМА — ані реєстру, ані denylist'а:
#   (1) контролер наш (`api/v1/…`) — відсікає фреймворкові монтування
#       (`cable`, `sidekiq`, `lookbook`, `up`) і Turbo-внутрішні
#       `*_historical_location`, не називаючи жодного з них;
#   (2) шлях ПОЗА `/api/` — відсікає JSON-контур, який layout не рендерить.
#
# ⚖️ Периметр свідомо ШИРШИЙ за «сторінки, які я бачив»: сегмент потрапляє в
# крихти й з POST-шляху, коли екшен перерендерює дашборд на помилці валідації.
# Сувора деривація «екшени, чиє ТІЛО кличе `render_dashboard`» дає менший набір і
# ДОКАЗОВО недобирає — рендер буває з приватного хелпера
# (`AccountSecurityController#render_password_error`), якого така деривація не
# бачить. Надлишкова мітка коштує чотирьох рядків YAML; відсутня — це і є той
# клас, проти якого гейт.
#
# 🔒 Стеля — що цей гейт НЕ бачить (зелений ≠ «крихти в порядку»):
#   · Лише БАЗОВА локаль. Ціна не росте з каталогом, а нова ще-неперекладена
#     локаль не червонить (`04_04 §12.10`); парність між локалями — вісь
#     `i18n-tasks missing`.
#   · Не перевіряє ЯКІСТЬ мітки — лише її наявність. Що «Trees» перекладено як
#     «Дерева», а не як «Ліси», тримає 👤-ревʼю (`00_07` I18N.1).
#   · Не перевіряє, що ВИКЛИКАЧ ходить через дім: `.humanize` повз
#     `DashboardLayout.breadcrumb_segment_label` лишиться тут зеленим. Це вісь
#     «одна деривація», і її тримає код-рев'ю + патерн `04_04 §12.14`.
#   · Динамічні сегменти (`:id`) не входять у популяцію взагалі — дім мітки
#     виводить їх числовим гардом ДО пошуку.
RSpec.describe "breadcrumb segment ↔ locale label parity" do # rubocop:disable RSpec/DescribeClass
  # Ліхтар на саму популяцію (§Guard-craft #28): якщо предикат перестане матчити,
  # набір тихо спорожніє, і обидві перевірки нижче зеленіли б, порівнюючи ніщо з
  # нічим. Поріг — куратований, помітно нижче факту: він ловить КОЛАПС деривації,
  # а не приріст маршрутів, тож новий ресурс його не рухає.
  let(:minimum_expected_segments) { 40 }
  let(:segments) { browser_contour_segments }
  let(:declared) { declared_labels }

  def browser_contour_segments
    Rails.application.routes.routes.filter_map { |route|
      next unless route.defaults[:controller].to_s.start_with?("api/v1/")

      path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      next if path.start_with?("/api/")

      path.split("/").reject { |s| s.empty? || s.start_with?(":") || s.start_with?("*") }
    }.flatten.uniq.sort
  end

  def declared_labels
    subtree = I18n.t(DashboardLayout::BREADCRUMB_SEGMENT_SCOPE, locale: I18n.default_locale, default: nil)
    subtree.is_a?(Hash) ? subtree.keys.map(&:to_s).sort : nil
  end


  it "derives a non-empty segment population from the router" do
    expect(segments.size).to be >= minimum_expected_segments,
      "деривація сегментів дала #{segments.size} (< #{minimum_expected_segments}) — предикат перестав матчити " \
      "браузерний контур, і перевірки нижче стали вакуумними"
  end

  it "resolves the label scope in the base locale" do
    expect(declared).not_to be_nil,
      "скоуп `#{DashboardLayout::BREADCRUMB_SEGMENT_SCOPE}` не резолвиться в піддерево базової локалі — " \
      "дім мітки перейменовано, а гейт лишився на старій адресі"
  end

  # `fallback: false` обов'язковий: fallbacks увімкнені в УСІХ середовищах
  # (`04_04 §12.2`), тож без прапорця порожня локаль «існує» через базову.
  it "has a base-locale label for every browser-contour segment" do
    missing = segments.reject do |segment|
      I18n.exists?("#{DashboardLayout::BREADCRUMB_SEGMENT_SCOPE}.#{segment}", I18n.default_locale, fallback: false)
    end

    expect(missing).to be_empty,
      "нема мітки `#{DashboardLayout::BREADCRUMB_SEGMENT_SCOPE}.<segment>` для: #{missing.join(', ')} — " \
      "ці крихти рендеряться англійським `.humanize` в усіх локалях"
  end

  # Зворотний бік — той, що не має симптомів: перейменований маршрут лишає
  # мітку, яку більше ніхто не читає, і жоден гейт про це не каже.
  it "has no orphaned label for a segment the router no longer serves" do
    orphans = (declared || []) - segments

    expect(orphans).to be_empty,
      "мітка без сегмента в маршрутах: #{orphans.join(', ')}"
  end
end
