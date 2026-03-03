# frozen_string_literal: true

FactoryBot.define do
  factory :gateway do
    sequence(:uid) { |n| "GW-%08X" % n }
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
