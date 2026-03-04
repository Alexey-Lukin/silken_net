# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password12345" }
    first_name { "Test" }
    last_name { "User" }
    role { :investor }
    organization

    trait :admin do
      first_name { "Olena" }
      last_name { "Kovalenko" }
      role { :admin }
    end

    trait :super_admin do
      first_name { "Artem" }
      last_name { "Volkov" }
      role { :super_admin }
    end

    trait :forester do
      first_name { "Dmytro" }
      last_name { "Bondarenko" }
      role { :forester }
    end

    trait :investor do
      first_name { "Maria" }
      last_name { "Shevchenko" }
      role { :investor }
    end
  end
end
