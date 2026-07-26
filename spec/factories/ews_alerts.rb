# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :ews_alert do
    cluster
    tree
    severity { :medium }
    alert_type { :severe_drought }
    status { :active }
    message_key { "hydrological_stress" }

    trait :drought do
      severity { :medium }
      alert_type { :severe_drought }
      message_key { "attractor_destabilised" }
      message_params { { z_value: 3.1 } }
    end

    trait :fire do
      severity { :critical }
      alert_type { :fire_detected }
      message_key { "fire_detected" }
      message_params { { temperature_c: 61.0, fire_limit: 60 } }
    end

    # [SLASH-1] Аудит на місці — cluster-level (tree nil), причина невизначена.
    trait :field_audit do
      severity { :critical }
      alert_type { :field_audit }
      tree { nil }
      message_key { "cluster_data_blackout" }
      message_params { { target_date: "2026-03-14" } }
    end
  end
end
