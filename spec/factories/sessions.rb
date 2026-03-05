# frozen_string_literal: true

FactoryBot.define do
  factory :session do
    user
    ip_address { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (RSpec Test)" }

    trait :mobile do
      user_agent { "SilkenNetMobile/2.1.0 (iOS 17)" }
    end

    trait :stale do
      created_at { 31.days.ago }
      updated_at { 31.days.ago }
    end

    trait :forester_session do
      association :user, factory: %i[user forester]
    end
  end
end
