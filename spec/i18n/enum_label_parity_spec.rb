# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт осі «джерело значень → базова локаль», якої CI структурно НЕ бачить.
#
# `i18n-tasks missing` звіряє локаль з локаллю, тож бачить лише «ключ є тут і
# нема там». Дві помилки він пропускає за побудовою: enum виріс, а YAML лишився
# (мітки немає) — і enum зменшився, а YAML лишився (мітка-сирота). Друга гірша,
# бо не має жодного симптому: рядок просто ніколи не читається.
#
# Раніше ця вісь була закрита рівно для ОДНОГО скоупа (`alerts.types`, у
# `text_formatter_parity_spec`). Саме тому `alerts.badge.severities.high` прожив
# у всіх чотирьох локалях, хоч `EwsAlert.severities` = low/medium/critical.
#
# Форма — **курована мапа як tripwire** (`00_06 §3`): новий user-visible enum
# додає сюди рядок; мертвий рядок (перейменований скоуп, знятий enum) мусить
# ЧЕРВОНІТИ, а не тихо перевірятись у порожнечу. Останнє стереже `sanity`-блок
# нижче — без нього «0 порушень» означало б «0 перевірок».
#
# 🔒 Стеля — що цей гейт НЕ бачить (зелений ≠ «i18n у порядку»):
#   · Лише БАЗОВА локаль, і це навмисно: ціна не росте з каталогом, а нова
#     ще-неперекладена локаль не робить гейт червоним (`04_04 §12.14`).
#     Парність між локалями — інша вісь, її тримає `i18n-tasks missing`.
#   · Лише ЗАРЕЄСТРОВАНІ пари. Enum, який рендериться сирим і скоупа не має
#     взагалі (`action_type`, `AuditLog#action`, breadcrumb-сегменти), сюди не
#     входить — він відкритий у `00_07` I18N.1.
#   · Для `token_type` цей гейт тримає ЛИШЕ повноту набору. Що базова мітка
#     дорівнює назві з контракту (`ERC20("…")`) — інша вісь, і її тримає
#     `spec/quality/token_ticker_parity_spec.rb` разом із символом.
#   · Не перевіряє, що ВИКЛИКАЧ ходить через скоуп: сайт із `.humanize` повз
#     спільну константу лишається тут зеленим (це вісь «одна деривація», і її
#     тримає код-рев'ю + патерн `04_04 §12.14`).
registry = [
  {
    name:   "EwsAlert#alert_type",
    scope:  TreeChronicle::TextFormatter::ALERT_TYPE_SCOPE,
    values: -> { EwsAlert.alert_types.keys }
  },
  {
    name:   "EwsAlert#severity",
    scope:  TreeChronicle::TextFormatter::SEVERITY_SCOPE,
    values: -> { EwsAlert.severities.keys }
  },
  {
    name:   "ActuatorCommand#status",
    scope:  "actuators.command_status_badge",
    values: -> { ActuatorCommand.statuses.keys }
  },
  {
    name:   "BlockchainTransaction#token_type",
    scope:  BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE,
    values: -> { BlockchainTransaction.token_types.keys }
  },
  {
    # [I18N.1] Найбільша родина дерева — і її сайти діляться на ТРИ роди вжитку
    # (показ ⊥ значення URL-параметра ⊥ логіка), два з яких мітки НЕ приймають.
    name:   "MaintenanceRecord#action_type",
    scope:  MaintenanceRecord::ACTION_TYPE_LABEL_SCOPE,
    values: -> { MaintenanceRecord.action_types.keys }
  },
  {
    name:   "AiInsight#insight_type",
    scope:  AiInsight::INSIGHT_TYPE_LABEL_SCOPE,
    values: -> { AiInsight.insight_types.keys }
  },
  {
    # [I18N.1] Роль видно на ЧОТИРЬОХ поверхнях, і одна з них — сайдбар, тобто
    # напис присутній на КОЖНІЙ сторінці дашборда.
    name:   "User#role",
    scope:  User::ROLE_LABEL_SCOPE,
    values: -> { User.roles.keys }
  },
  {
    # [I18N.1/ARCH.75] Рід пристрою читає не лише картка актуатора, а й аварійний
    # алерт про НЕ-дію — там пристрою може не існувати взагалі, тож клас лишається
    # єдиним, чим подію можна назвати.
    name:   "Actuator#device_type",
    scope:  Actuator::DEVICE_TYPE_LABEL_SCOPE,
    values: -> { Actuator.device_types.keys }
  },
  {
    # Тут джерело — не одна модель, а сама курована мапа StatusBadge: вона
    # обслуговує вісім родин станів одразу, тож «enum» для неї = її ж ключі.
    # `aria_label` — не стан, а шаблон обгортки; єдиний свідомий виняток.
    name:    "Views::Shared::UI::StatusBadge::STYLES",
    scope:   "ui.status",
    values:  -> { Views::Shared::UI::StatusBadge::STYLES.keys.map(&:to_s) },
    exclude: %w[aria_label]
  }
].freeze

RSpec.describe "enum ↔ locale label parity" do # rubocop:disable RSpec/DescribeClass
  def declared_labels(scope, exclude)
    subtree = I18n.t(scope, locale: I18n.default_locale, default: nil)
    return nil unless subtree.is_a?(Hash)

    subtree.keys.map(&:to_s) - exclude
  end

  registry.each do |entry|
    describe entry[:name] do
      let(:values)   { entry[:values].call.map(&:to_s) }
      let(:exclude)  { entry[:exclude] || [] }
      let(:declared) { declared_labels(entry[:scope], exclude) }

      # Сама реєстрація мусить бути живою. Перейменований/видалений скоуп дає
      # `nil`, а порожній набір значень означає, що дві наступні перевірки
      # порівнюють ніщо з нічим і зеленіють безпідставно.
      it "is a live registry entry (scope resolves, source is non-empty)" do
        expect(declared).not_to be_nil,
          "scope `#{entry[:scope]}` не резолвиться в піддерево базової локалі — мертвий рядок реєстру"
        expect(values).not_to be_empty,
          "джерело значень для #{entry[:name]} порожнє — перевірки нижче вакуумні"
      end

      # `fallback: false` обов'язковий: fallbacks увімкнені в УСІХ середовищах
      # (`04_04 §12.2`), тож без прапорця порожня локаль «існує» через базову.
      it "has a base-locale label for every value" do
        missing = values.reject do |value|
          I18n.exists?("#{entry[:scope]}.#{value}", I18n.default_locale, fallback: false)
        end

        expect(missing).to be_empty,
          "нема мітки `#{entry[:scope]}.<value>` для: #{missing.join(', ')}"
      end

      # Зворотний бік — той, що не має симптомів і тому потребує гейта.
      it "has no orphaned label for a value the source no longer defines" do
        orphans = (declared || []) - values

        expect(orphans).to be_empty,
          "мітка без значення в джерелі: #{orphans.join(', ')}"
      end
    end
  end
end
