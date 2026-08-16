# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module TreeChronicle
  # = ===================================================================
  # 📝 TEXT FORMATTER (i18n-Ready Chronicle Text Templates)
  # = ===================================================================
  # Централізує всі текстові шаблони хроніки дерева.
  # Мітки alert_type локалізовані (`alerts.types.*`, 4 локалі) — решта шаблонів
  # ще англомовні рядки; їхня локалізація трекається в 00_07 I18N.1.
  module TextFormatter
    module_function

    # --- AiInsight: Homeostasis ---
    def homeostasis_title
      "Deep Homeostasis"
    end

    def homeostasis_description(insight)
      z_value = insight.avg_z || "N/A"
      "Tree entered deep homeostasis. Z-value stable: #{z_value} \u03c3"
    end

    # --- AiInsight: Stress ---
    def stress_title
      "Elevated Stress Detected"
    end

    # [ARCH.84] Асиметрія жила в ОДНОМУ тілі: `max_temp` рядком нижче чесно
    # віддавав «N/A», а `stress_index` підставляв нуль — під заголовком «Elevated
    # Stress Detected», тобто запис у хроніку дерева стверджував нульовий стрес
    # рівно там, де його оголошено підвищеним. `ai_insights.stress_index`
    # легально `NULL` (`allow_nil` + nullable-колонка), а нуль тут ДОСЯЖНИЙ —
    # `calculate_stress_index_heuristic` віддає рівно `0.0` здоровому дереву.
    def stress_description(insight)
      stress_pct = insight.stress_index ? "#{(insight.stress_index * 100).round(1)}%" : "N/A"
      max_temp = insight.max_temp || "N/A"
      "Stress index: #{stress_pct}. Max temperature: #{max_temp}\u00b0C. Recommendation: monitoring"
    end

    # --- AiInsight: Fraud ---
    def fraud_title
      "AI Guard Anomaly"
    end

    def fraud_description(insight)
      # deviation_from_baseline — частка 0.0..1.0 (напр. 0.35 = 35%), як
      # повертає InsightGeneratorService#calculate_deviation. Масштабуємо ×100,
      # як робить stress_description для stress_index — раніше рендерилось "0.35%"
      # замість "35%" (заниження fraud-сигналу інвесторам на два порядки).
      deviation = insight.deviation_from_baseline
      deviation_pct = deviation ? (deviation.to_f * 100).round(1) : "N/A"
      "AI Guard detected anomaly: sap_flow deviation from baseline > #{deviation_pct}%"
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
      "emergency_response_undeliverable" => "\u{1F6AB}"
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
      alert.message || "Alert triggered"
    end

    # --- EwsAlert: Recovery ---
    def recovery_title
      "Incident Resolved"
    end

    def recovery_description(alert)
      duration = if alert.resolved_at && alert.created_at
                   days = ((alert.resolved_at - alert.created_at) / 1.day).round
                   "Duration: #{days} #{"day".pluralize(days)}."
      else
                   ""
      end
      notes = alert.resolution_notes.present? ? " #{alert.resolution_notes}" : ""
      "Incident closed.#{" " + duration if duration.present?}#{notes}".strip
    end

    # --- MaintenanceRecord ---
    def maintenance_title(record)
      record.action_type.to_s.humanize
    end

    def maintenance_description(record)
      technician = record.user&.full_name || "Unknown"
      notes = record.notes.present? ? record.notes.truncate(120) : "No notes"
      "Technician #{technician}: #{notes}"
    end

    # --- BlockchainTransaction ---
    # [ARCH.101] Напрямок не видно ні з колонки, ні зі знака `amount` (слеш пишеться
    # ДОДАТНИМ) — тому обидва рядки деривують його через `#burn?`, а не приймають
    # мінт за замовчуванням. Доти ім'я методу саме стверджувало напрямок
    # («minting_title»), тож викликач не мав де помітити, що стверджує неправду.
    def blockchain_title(tx)
      token = tx.token_type.to_s.humanize
      tx.burn? ? "#{token} Burned" : "#{token} Minted"
    end

    def blockchain_description(tx)
      amount = tx.amount
      network = (tx.blockchain_network || "Polygon").capitalize
      verb = tx.burn? ? "Burned" : "Minted"
      "#{verb} #{amount} tokens on #{network}"
    end
  end
end
