# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :audit_log do
    user
    organization { user.organization }
    # [TEST.12] Лише РЕАЛЬНІ значення писачів (12 літералів + 3 `_to_`-родини +
    # blockchain_tx_{event}) — доти дефолт «update_settings» був вигаданим.
    action { "system_parameter_changed" }
    metadata { { field: "critical_z", old_value: 100, new_value: 200 } }
    ip_address { "192.168.1.#{rand(1..254)}" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" }

    trait :with_auditable do
      association :auditable, factory: :cluster
    end
  end
end
