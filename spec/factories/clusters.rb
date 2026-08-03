# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :cluster do
    # [TEST.11] `clusters.name` — unique-індекс; суфікс розводить процеси.
    sequence(:name) { |n| "Sector #{n}-#{SecureRandom.hex(3)}" }
    region { "Cherkasy Oblast" }
    organization
  end
end
