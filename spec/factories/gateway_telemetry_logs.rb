# frozen_string_literal: true

FactoryBot.define do
  factory :gateway_telemetry_log do
    association :gateway
    queen_uid           { gateway.uid }
    voltage_mv          { 4200 }
    temperature_c       { 25.0 }
    cellular_signal_csq { 15 }

    # gateway_id is a legacy NOT-NULL column in the DB; the model uses queen_uid
    # as the logical FK (belongs_to :gateway, foreign_key: :queen_uid).
    # We must populate both so the DB constraint is satisfied.
    after(:build) do |log|
      log[:gateway_id] = log.gateway.id if log.gateway&.persisted?
    end

    after(:create) do |log|
      log.update_column(:gateway_id, log.gateway.id) if log.gateway&.persisted?
    end

    trait :low_battery do
      voltage_mv { GatewayTelemetryLog::LOW_BATTERY_THRESHOLD - 100 }
    end

    trait :overheated do
      temperature_c { GatewayTelemetryLog::OVERHEAT_THRESHOLD + 1 }
    end

    trait :weak_signal do
      cellular_signal_csq { GatewayTelemetryLog::LOW_SIGNAL_THRESHOLD - 1 }
    end

    trait :unknown_signal do
      cellular_signal_csq { 99 }
    end
  end
end
