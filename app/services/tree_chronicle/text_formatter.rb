# frozen_string_literal: true

module TreeChronicle
  # = ===================================================================
  # 📝 TEXT FORMATTER (i18n-Ready Chronicle Text Templates)
  # = ===================================================================
  # Централізує всі текстові шаблони хроніки дерева.
  # [i18n-READY]: Кожен метод повертає рядок. При додаванні I18n достатньо
  # замінити рядки на I18n.t("chronicle.homeostasis", z_value: ...) без зміни
  # інтерфейсу або архітектури.
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
      deviation = insight.deviation_from_baseline || "N/A"
      "AI Guard detected anomaly: sap_flow deviation from baseline > #{deviation}%"
    end

    # --- EwsAlert ---
    def alert_icon(alert_type)
      case alert_type.to_s
      when "fire_detected"     then "\u{1F525}"
      when "severe_drought"    then "\u{1F4A7}"
      when "insect_epidemic"   then "\u{1F41B}"
      when "vandalism_breach"  then "\u{1F6A8}"
      when "seismic_anomaly"   then "\u{1F30D}"
      when "system_fault"      then "\u26A0"
      when "field_audit"       then "\u{1F50D}"
      else "\u26A0"
      end
    end

    def alert_title(alert)
      case alert.alert_type.to_s
      when "fire_detected"     then "Fire Detected"
      when "severe_drought"    then "Severe Drought"
      when "insect_epidemic"   then "Insect Epidemic"
      when "vandalism_breach"  then "Vandalism Breach"
      when "seismic_anomaly"   then "Seismic Anomaly"
      when "system_fault"      then "System Fault"
      when "field_audit"       then "Field Audit"
      else alert.alert_type.to_s.humanize
      end
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
      "Verified by Chainlink Oracle. Minted #{amount} tokens on #{network.capitalize}"
    end
  end
end
