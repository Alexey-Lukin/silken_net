# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :gateway do
    # [TEST.11] Див. `trees.rb` — той самий патерн; `UID_FORMAT` теж вимагає
    # рівно 8 hex у верхньому регістрі.
    sequence(:uid, 900_000) { |n| "SNET-Q-#{format('%04X', n % 0x10000)}#{SecureRandom.hex(2).upcase}" }
    config_sleep_interval_s { 300 }
    state { :idle }
    last_seen_at { Time.current }
    ip_address { "192.168.1.#{rand(1..254)}" }
    cluster

    trait :online do
      last_seen_at { Time.current }
    end

    trait :offline do
      last_seen_at { 2.hours.ago }
    end

    trait :geolocated do
      latitude { 49.4285 }
      longitude { 32.0620 }
    end
  end
end
