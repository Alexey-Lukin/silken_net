# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # [TEST.11] `users.email_address` — unique-індекс; суфікс розводить процеси.
    sequence(:email_address) { |n| "user#{n}-#{SecureRandom.hex(4)}@example.com" }
    password { "password12345" }
    first_name { "Test" }
    last_name { "User" }
    role { :subscriber }
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

    trait :subscriber do
      first_name { "Maria" }
      last_name { "Shevchenko" }
      role { :subscriber }
    end
  end
end
