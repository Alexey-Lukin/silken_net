# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :cluster do
    # [TEST.11] `clusters.name` — unique-індекс; суфікс розводить процеси.
    sequence(:name) { |n| "Sector #{n}-#{SecureRandom.hex(3)}" }
    region { "Cherkasy Oblast" }
    # [SEC.37] Зона ділянки — обовʼязкова; пара «Черкаси + UTC» була б вигаданою.
    time_zone { "Europe/Kyiv" }
    organization
  end
end
