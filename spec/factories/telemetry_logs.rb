# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :telemetry_log do
    tree
    bio_status { :homeostasis }
    voltage_mv { 4200 }
    temperature_c { 22.5 }
    acoustic_events { 5 }
    metabolism_s { 120 }
    growth_points { 10 }
    # Direct normal-пакет: стартовий DEFAULT_TTL=3 без жодного relay
    # (5 — wire-неможливе для non-panic; TelemetryLog::INITIAL_TTL_*).
    mesh_ttl { 3 }
    # 🔴 [TEST.12] Було 0.35 — та сама до-FW.8 реліквія, яку трейт `:optimal` нижче
    # уже полагодив у себе й лишив тут: реальні Z ідуть у 2.0..45.0. Дефолт мусить
    # бути ВАЛІДНИЙ, але НЕоптимальний, інакше трейт перестає щось означати.
    z_value { 25.0 }
    rssi { -65 }

    trait :healthy do
      bio_status { :homeostasis }
      temperature_c { 22.5 }
      acoustic_events { 5 }
    end

    trait :stressed do
      bio_status { :stress }
      temperature_c { 35.0 }
      acoustic_events { 30 }
    end

    trait :anomaly do
      bio_status { :anomaly }
      temperature_c { 55.0 }
      acoustic_events { 80 }
    end

    # [SLASH-1] status=3 = софт-збій прошивки (vm_error), НЕ tamper —
    # справжня пилка їде panic-каналом (PANIC_FLAG, status=homeostasis).
    trait :vm_errored do
      bio_status { :vm_error }
    end

    trait :optimal do
      bio_status { :homeostasis }
      voltage_mv { 4200 }
      temperature_c { 22.5 }
      acoustic_events { 5 }
      # Lorenz attractor optimum (FW.8 / BioContract::OPTIMAL_Z_TARGET).
      # Раніше факторі вживали 0.35 — реліквія до-FW.8 normalised range;
      # реальні Z значення йдуть у 2.0..45.0, з sweet spot ≈ 29.0.
      z_value { 29.0 }
    end

    # Повністю верифікована телеметрія для trustless мінтингу.
    # IoTeX W3bstream + Chainlink Oracle — обидва підтвердження присутні.
    trait :verified_telemetry do
      verified_by_iotex { true }
      zk_proof_ref { "zk-proof-#{SecureRandom.hex(8)}" }
      chainlink_request_id { "chainlink-req-#{SecureRandom.hex(8)}" }
      oracle_status { "fulfilled" }
    end

    trait :hot do
      temperature_c { 55.0 }
    end
  end
end
