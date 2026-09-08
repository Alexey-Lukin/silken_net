# SPDX-License-Identifier: AGPL-3.0-or-later
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

    trait :freezing do
      temperature_c { GatewayTelemetryLog::LOW_TEMPERATURE_THRESHOLD - 1 }
    end

    trait :weak_signal do
      cellular_signal_csq { GatewayTelemetryLog::LOW_SIGNAL_THRESHOLD - 1 }
    end

    trait :unknown_signal do
      cellular_signal_csq { 99 }
    end

    # [FW.59] Причина ребута — старші ТРИ біти health_flags (wire-дім:
    # firmware/common/reset_cause.h). Значення тут ЛІТЕРАЛЬНІ навмисно: узяти
    # їх з `RESET_CAUSES.index(…) << HFLAG_RESET_SHIFT` означало б рахувати
    # фікстуру тим самим перетворенням, що й код, — і пін перестав би судити
    # саме те, заради чого існує.
    trait :watchdog_reset  do health_flags { 0x80 } end  # iwdg      (4 << 5)
    trait :hardfault_reset do health_flags { 0xC0 } end  # hardfault (6 << 5)
    trait :clean_reboot    do health_flags { 0x20 } end  # power_on  (1 << 5)
  end
end
