# frozen_string_literal: true

FactoryBot.define do
  factory :actuator_command do
    actuator
    command_payload { "OPEN" }
    duration_seconds { 60 }
    status { :issued }
    priority { :low }

    trait :high_priority do
      priority { :high }
    end

    trait :override_stop do
      command_payload { "STOP" }
      priority { :override }
    end

    trait :override_emergency do
      command_payload { "EMERGENCY_SHUTDOWN" }
      priority { :override }
    end

    trait :with_ttl do
      expires_at { 30.minutes.from_now }
    end

    trait :expired do
      expires_at { 1.hour.from_now }
      after(:create) do |cmd|
        cmd.update_columns(expires_at: 1.minute.ago)
      end
    end
  end
end
