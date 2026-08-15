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

    def stress_description(insight)
      stress_pct = ((insight.stress_index || 0) * 100).round(1)
      max_temp = insight.max_temp || "N/A"
      "Stress index: #{stress_pct}%. Max temperature: #{max_temp}\u00b0C. Recommendation: monitoring"
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
    # \u0414\u0456\u043C \u043C\u0456\u0442\u043E\u043A alert_type \u2014 `config/locales/alerts/*.yml`. \u041A\u043B\u044E\u0447 \u0434\u0435\u0440\u0438\u0432\u0443\u0454\u0442\u044C\u0441\u044F
    # \u0427\u0415\u0420\u0415\u0417 \u0446\u044E \u043A\u043E\u043D\u0441\u0442\u0430\u043D\u0442\u0443 \u0432 \u0443\u0441\u0456\u0445 \u0432\u0438\u043A\u043B\u0438\u043A\u0430\u0447\u0430\u0445 \u0456 \u0432 \u0441\u043F\u0435\u0446\u0456, \u0442\u043E\u0436 \u0434\u0440\u0443\u043A\u0430\u0440\u0441\u044C\u043A\u0430 \u043F\u043E\u043C\u0438\u043B\u043A\u0430 \u0432
    # \u043D\u0435\u0439\u043C\u0441\u043F\u0435\u0439\u0441\u0456 \u0432\u0430\u043B\u0438\u0442\u044C \u0433\u0435\u0439\u0442, \u0430 \u043D\u0435 \u043F\u0440\u043E\u0445\u043E\u0434\u0438\u0442\u044C \u0437\u0435\u043B\u0435\u043D\u043E\u044E.
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

    # \u0413\u043B\u0456\u0444\u0438 locale-\u0456\u043D\u0432\u0430\u0440\u0456\u0430\u043D\u0442\u043D\u0456 \u2192 \u0434\u0456\u043C \u0442\u0443\u0442, \u043D\u0435 \u0432 YAML: parity-\u0433\u0435\u0439\u0442 `i18n-tasks
    # missing` \u0456\u043D\u0430\u043A\u0448\u0435 \u0437\u043C\u0443\u0441\u0438\u0432 \u0431\u0438 \u0442\u0440\u0438\u043C\u0430\u0442\u0438 \u0447\u043E\u0442\u0438\u0440\u0438 \u043E\u0434\u043D\u0430\u043A\u043E\u0432\u0456 \u043A\u043E\u043F\u0456\u0457 \u043A\u043E\u0436\u043D\u043E\u0433\u043E \u0435\u043C\u043E\u0434\u0437\u0456.
    ALERT_ICONS = {
      "severe_drought"       => "\u{1F4A7}",
      "insect_epidemic"      => "\u{1F41B}",
      "vandalism_breach"     => "\u{1F6A8}",
      "fire_detected"        => "\u{1F525}",
      "seismic_anomaly"      => "\u{1F30D}",
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

    # Fail-open: \u043D\u0435\u0432\u0456\u0434\u043E\u043C\u0438\u0439 \u0442\u0438\u043F \u043C\u0430\u043B\u044E\u0454 generic-\u043F\u043E\u043F\u0435\u0440\u0435\u0434\u0436\u0435\u043D\u043D\u044F, \u0430 \u043D\u0435 \u0432\u0430\u043B\u0438\u0442\u044C \u0441\u0442\u043E\u0440\u0456\u043D\u043A\u0443.
    # \u0421\u0442\u0435\u043B\u044F \u0441\u0432\u0456\u0434\u043E\u043C\u0430 \u2014 \u043F\u043E\u0432\u043D\u043E\u0442\u0443 \u043C\u0430\u043F\u0438 \u043F\u0440\u043E\u0442\u0438 enum'\u0430 \u0441\u0442\u0435\u0440\u0435\u0436\u0435 \u0441\u043F\u0435\u043A\u0430, \u0431\u043E \u0436\u043E\u0434\u0435\u043D CI-\u0433\u0435\u0439\u0442
    # \u0446\u0456\u0454\u0457 \u043E\u0441\u0456 \u043D\u0435 \u0431\u0430\u0447\u0438\u0442\u044C (`i18n-tasks` \u0437\u0432\u0456\u0440\u044F\u0454 \u043B\u043E\u043A\u0430\u043B\u044C \u0437 \u043B\u043E\u043A\u0430\u043B\u043B\u044E, \u043D\u0435 \u0437 \u043C\u043E\u0434\u0435\u043B\u043B\u044E).
    ALERT_ICON_FALLBACK = "\u26A0"

    def alert_icon(alert_type)
      ALERT_ICONS.fetch(alert_type.to_s, ALERT_ICON_FALLBACK)
    end

    # `default:` \u0442\u0440\u0438\u043C\u0430\u0454 \u0442\u043E\u0439 \u0441\u0430\u043C\u0438\u0439 fail-open \u043A\u043E\u043D\u0442\u0440\u0430\u043A\u0442, \u0449\u043E \u0439 ALERT_ICON_FALLBACK.
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
    def minting_title(tx)
      token = tx.token_type.to_s.humanize
      "#{token} Minted"
    end

    def minting_description(tx)
      amount = tx.amount
      network = tx.blockchain_network || "Polygon"
      "Minted #{amount} tokens on #{network.capitalize}"
    end
  end
end
