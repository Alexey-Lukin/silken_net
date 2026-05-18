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
    mesh_ttl { 5 }
    z_value { 0.35 }
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

    trait :tampered do
      bio_status { :tamper_detected }
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

    trait :seismic do
      piezo_voltage_mv { 2000 }
    end

    trait :hot do
      temperature_c { 55.0 }
    end

    trait :pest_swarm do
      acoustic_events { 80 }
    end
  end
end
