# frozen_string_literal: true

FactoryBot.define do
  factory :identity do
    user
    provider { "google_oauth2" }
    sequence(:uid) { |n| "google_uid_#{n}" }
    access_token  { SecureRandom.hex(16) }
    refresh_token { SecureRandom.hex(16) }
    expires_at    { 1.hour.from_now }
    auth_data     { { "provider" => "google_oauth2", "uid" => uid } }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :apple do
      provider { "apple" }
      sequence(:uid) { |n| "apple_uid_#{n}" }
    end

    trait :facebook do
      provider { "facebook" }
      sequence(:uid) { |n| "facebook_uid_#{n}" }
    end

    trait :linkedin do
      provider { "linkedin" }
      sequence(:uid) { |n| "linkedin_uid_#{n}" }
    end

    trait :twitter do
      provider { "twitter" }
      sequence(:uid) { |n| "twitter_uid_#{n}" }
    end

    trait :no_expiry do
      expires_at { nil }
    end

    trait :locked do
      locked_at { Time.current }
    end

    trait :primary_identity do
      primary { true }
    end
  end
end
