# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module TreeChronicle
  # = ===================================================================
  # 📝 TEXT FORMATTER (i18n-Ready Chronicle Text Templates)
  # = ===================================================================
  # Централізує всі текстові шаблони хроніки дерева.
  #
  # [I18N.1] Шаблони живуть у `trees.chronicle.templates.*` (4 локалі); мітки
  # доменних enum'ів беруться з ВЛАСНИХ домів (`alerts.types.*` через
  # `ALERT_TYPE_SCOPE`, `MaintenanceRecord.action_type_label`,
  # `BlockchainTransaction.token_type_label`) — тут вони не дублюються.
  # Хроніка будується в РЕНДЕР-ЧАС і нікуди не персиститься, тож локаль тут
  # завжди локаль ГЛЯДАЧА; ⛔ не кешувати ці рядки поза межами запиту.
  # Умовний фрагмент («спалено» ⊥ «намінтовано») — ОКРЕМИЙ ключ, а не булевий
  # параметр: в іншій мові він може стояти в іншому місці речення.
  module TextFormatter
    module_function

    # ОДНА деривація ключа шаблону — друкарська помилка в неймспейсі валить усі
    # шаблони одразу, а не проходить тихо одним рядком.
    TEMPLATE_SCOPE = "trees.chronicle.templates"

    def template(key, **args)
      I18n.t("#{TEMPLATE_SCOPE}.#{key}", **args)
    end

    # --- AiInsight: Homeostasis ---
    def homeostasis_title
      template("homeostasis.title")
    end

    def homeostasis_description(insight)
      template("homeostasis.description", z_value: insight.avg_z || template("not_available"))
    end

    # --- AiInsight: Stress ---
    def stress_title
      template("stress.title")
    end

    # [ARCH.84] Асиметрія жила в ОДНОМУ тілі: `max_temp` рядком нижче чесно
    # віддавав «N/A», а `stress_index` підставляв нуль — під заголовком «Elevated
    # Stress Detected», тобто запис у хроніку дерева стверджував нульовий стрес
    # рівно там, де його оголошено підвищеним. `ai_insights.stress_index`
    # легально `NULL` (`allow_nil` + nullable-колонка), а нуль тут ДОСЯЖНИЙ —
    # `calculate_stress_index_heuristic` віддає рівно `0.0` здоровому дереву.
    def stress_description(insight)
      stress_pct = insight.stress_index ? "#{(insight.stress_index * 100).round(1)}%" : template("not_available")
      template("stress.description",
               stress: stress_pct,
               max_temp: insight.max_temp || template("not_available"))
    end

    # --- AiInsight: Fraud ---
    def fraud_title
      template("fraud.title")
    end

    def fraud_description(insight)
      # deviation_from_baseline — частка 0.0..1.0 (напр. 0.35 = 35%), як
      # повертає InsightGeneratorService#calculate_deviation. Масштабуємо ×100,
      # як робить stress_description для stress_index — раніше рендерилось "0.35%"
      # замість "35%" (заниження fraud-сигналу інвесторам на два порядки).
      deviation = insight.deviation_from_baseline
      deviation_pct = deviation ? (deviation.to_f * 100).round(1) : template("not_available")
      template("fraud.description", deviation: deviation_pct)
    end

    # --- EwsAlert ---
    # Дім міток alert_type — `config/locales/alerts/*.yml`. Ключ деривується
    # ЧЕРЕЗ цю константу в усіх викликачах і в спеці, тож друкарська помилка в
    # неймспейсі валить гейт, а не проходить зеленою.
    ALERT_TYPE_SCOPE = "alerts.types"

    # Дім міток severity — поруч із типами, а НЕ під компонентом, який перший їх
    # показав: власник значень — модель. (Історія: скоуп жив під `alerts.badge.*`,
    # доки `Alerts::Badge` не знято 2026-07-27 як UI без жодного рендерера — саме
    # такий переїзд і доводить, що прив'язка до компонента була помилкою.)
    # Спільна константа потрібна, доки викликачів ДВА і більше: дві деривації
    # означають, що друкарська помилка в одній лишається зеленою назавжди.
    SEVERITY_SCOPE = "alerts.severities"

    # [I18N.1] Дім міток `Entry#event_type` — синтетичного роду події, який
    # виробляє САМ сервіс (`:alert`/`:fraud`/`:stress`/`:maintenance`/`:minting`/
    # `:recovery`/`:homeostasis`). ⚠️ Це НЕ enum моделі, і саме тому клас випав з
    # усіх переліків: гейт парності будується на `Model.enum.keys`, а тут enum'а
    # немає за побудовою — множину дає код сервісу.
    EVENT_TYPE_SCOPE = "trees.chronicle.event_types"

    # ОДНА деривація ключа. Fail-open: новий рід події рендериться сирим, доки
    # мітка не доїде в локалі.
    def self.event_type_label(event_type)
      value = event_type.to_s
      I18n.t("#{EVENT_TYPE_SCOPE}.#{value}", default: value)
    end

    # Гліфи locale-інваріантні → дім тут, не в YAML: parity-гейт `i18n-tasks
    # missing` інакше змусив би тримати чотири однакові копії кожного емодзі.
    ALERT_ICONS = {
      "severe_drought"       => "\u{1F4A7}",
      "vandalism_breach"     => "\u{1F6A8}",
      "fire_detected"        => "\u{1F525}",
      "system_fault"         => "\u26A0",
      "entropy_anomaly"      => "\u{1F4C9}",
      "field_audit"          => "\u{1F50D}",
      "queen_offline"        => "\u{1F4F4}",
      "queen_uplink_lost"    => "\u{1F4E1}",
      "chainsaw_detected"    => "\u{1FA9A}",
      "firmware_fault"       => "\u2699",
      "firmware_reverted"    => "\u23EE",
      "firmware_canary_trip" => "\u{1F424}",
      "actuator_stuck"       => "\u{1F527}",
      "emergency_response_undeliverable" => "\u{1F6AB}",
      "gateway_uplink_degraded" => "\u{1F4E1}",
      "hardware_fault" => "\u{1F527}",
      "slash_dispatch_failed" => "\u{1F4B8}"
    }.freeze

    # Fail-open: невідомий тип малює generic-попередження, а не валить сторінку.
    # Стеля свідома — повноту мапи проти enum'а стереже спека, бо жоден CI-гейт
    # цієї осі не бачить (`i18n-tasks` звіряє локаль з локаллю, не з моделлю).
    ALERT_ICON_FALLBACK = "\u26A0"

    def alert_icon(alert_type)
      ALERT_ICONS.fetch(alert_type.to_s, ALERT_ICON_FALLBACK)
    end

    # `default:` тримає той самий fail-open контракт, що й ALERT_ICON_FALLBACK.
    def alert_title(alert)
      type = alert.alert_type.to_s
      I18n.t("#{ALERT_TYPE_SCOPE}.#{type}", default: type.humanize)
    end

    def alert_severity_label(alert)
      severity = alert.severity.to_s
      I18n.t("#{SEVERITY_SCOPE}.#{severity}", default: severity.humanize)
    end

    def alert_description(alert)
      alert.message || template("alert.fallback_description")
    end

    # --- EwsAlert: Recovery ---
    def recovery_title
      template("recovery.title")
    end

    # Тривалість іде через `distance_of_time_in_words`, а не власний plural-блок:
    # інцидент здебільшого коротший за добу, тож ОДИНИЦЮ мусить обирати шкала, а
    # не ми («близько 3 годин», не «0 днів» — округлення до діб дає нуль на всьому,
    # що вирішили того ж дня). Форми для всіх наших мов уже несе `rails-i18n`
    # ([`04_04 §12.2`](../../../docs/04_04_Phlex_UI_and_Tailwind.md)), тож наш ключ
    # лишається рамкою з простою інтерполяцією й plural-осі не має взагалі.
    def recovery_description(alert)
      duration = if alert.resolved_at && alert.created_at
                   template("recovery.duration",
                            duration: ActionController::Base.helpers.distance_of_time_in_words(
                              alert.created_at, alert.resolved_at
                            ))
      else
                   ""
      end
      # [I18N.1] Рендер записів — локаллю глядача в момент показу (дім —
      # `EwsAlert#resolution_texts`); людський text-запис їде як є.
      texts = alert.resolution_texts
      notes = texts.any? ? " #{texts.join(" ")}" : ""
      "#{template('recovery.description')}#{" " + duration if duration.present?}#{notes}".strip
    end

    # --- MaintenanceRecord ---
    # [I18N.1] Через ДІМ мітки, не `.humanize`: доти цей рядок обходив
    # `MaintenanceRecord.action_type_label`, тобто той самий файл ніс і ратифіковану
    # форму (`alert_title` ↑), і її порушення.
    def maintenance_title(record)
      MaintenanceRecord.action_type_label(record.action_type)
    end

    def maintenance_description(record)
      template("maintenance.description",
               technician: record.user&.full_name || template("maintenance.unknown_technician"),
               notes: record.notes.presence&.truncate(120) || template("maintenance.no_notes"))
    end

    # --- BlockchainTransaction ---
    # [ARCH.101] Напрямок не видно ні з колонки, ні зі знака `amount` (слеш пишеться
    # ДОДАТНИМ) — тому обидва рядки деривують його через `#burn?`, а не приймають
    # мінт за замовчуванням. Доти ім'я методу саме стверджувало напрямок
    # («minting_title»), тож викликач не мав де помітити, що стверджує неправду.
    # [I18N.1] Мітка токена — з ДОМУ (`token_type_label`), не `.humanize`; напрямок —
    # ДВА окремі ключі, не булевий параметр: в іншій мові дієслово стоїть в іншому
    # місці речення, тож фрагмент фрази параметром зробив би переклад неможливим.
    def blockchain_title(tx)
      token = BlockchainTransaction.token_type_label(tx.token_type)
      template(tx.burn? ? "blockchain.burned_title" : "blockchain.minted_title", token: token)
    end

    def blockchain_description(tx)
      network = (tx.blockchain_network || "Polygon").capitalize
      template(tx.burn? ? "blockchain.burned_description" : "blockchain.minted_description",
               amount: tx.amount, network: network)
    end
  end
end
