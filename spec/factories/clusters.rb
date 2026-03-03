# frozen_string_literal: true

FactoryBot.define do
  factory :cluster do
    sequence(:name) { |n| "Sector #{n}" }
    region { "Cherkasy Oblast" }
    organization
  end
end
