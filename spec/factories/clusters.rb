# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :cluster do
    sequence(:name) { |n| "Sector #{n}" }
    region { "Cherkasy Oblast" }
    organization
  end
end
