# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :tree do
    # [TEST.11] sequence лишається гарантією унікальності ВСЕРЕДИНІ процесу,
    # випадкова половина — роздільник МІЖ процесами: лічильник стартує з тієї
    # самої позиції в кожному процесі, тож два писачі в одну БД видавали
    # ідентичні значення на unique-колонці. Формат несучий: `DID_FORMAT`
    # вимагає рівно 8 hex у верхньому регістрі.
    sequence(:did, 900_000) { |n| "SNET-#{format('%04X', n % 0x10000)}#{SecureRandom.hex(2).upcase}" }
    latitude { 49.4285 }
    longitude { 32.0620 }
    status { :active }
    tree_family
    cluster
  end
end
