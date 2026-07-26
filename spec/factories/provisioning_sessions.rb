# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :provisioning_session do
    operator    { association(:user, :super_admin) }
    supervisor  { association(:user, :admin) }
    sequence(:device_uid) { |n| "DEVICE-#{n.to_s(16).rjust(8, '0').upcase}" }
    sequence(:batch_id)   { |n| "BATCH-#{n}" }
    gilka            { "A" }
    firmware_version { "fw-1.2.3" }
    flash_addr       { "0x0803E000" }
    rdp_level        { 1 }

    trait :gilka_b do
      gilka { "B" }
      sequence(:se_serial_hex) { |n| n.to_s(16).rjust(18, "0").upcase }
    end

    trait :supervisor_approved do
      supervisor_approved_at { Time.current }
      state { "supervisor_approved" }
    end

    trait :active do
      supervisor_approved
      started_at { Time.current }
      state { "active" }
    end
  end
end
