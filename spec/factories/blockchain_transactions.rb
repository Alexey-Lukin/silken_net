# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :blockchain_transaction do
    wallet
    amount { 10.0 }
    token_type { :carbon_coin }
    status { :confirmed }
    to_address { "0x1234567890abcdef1234567890abcdef12345678" }
    tx_hash { "0x#{SecureRandom.hex(32)}" }
    notes { "Test minting transaction" }

    # [ARCH.95] Форма СЛЕШ-інтенту, взята з єдиного реального писача
    # (`BlockchainBurningService#create_slash_intent!`): ДОДАТНА сума + `sourceable`
    # контракту + ЯВНИЙ `direction: :burn`.
    #
    # 🔴 Трейт існує саме тому, що пара неподільна, а половина її ловиться лише
    # інваріантом моделі: фікстура з `sourceable` без напрямку описувала б стан,
    # якого писач створити НЕ МОЖЕ — і до ARCH.95 таких фікстур було пʼятнадцять,
    # бо доти напрямок деривувався і половини не існувало.
    # ⛔ Не деривувати `direction` з `sourceable_type` в `after(:build)`: це
    # відновило б рівно ту деривацію, яку присуд зняв, і сховало б від спек
    # обовʼязок писача оголошувати напрямок.
    trait :slash_burn do
      direction { :burn }
      sourceable factory: :naas_contract
      notes { "🚨 SLASHING: Кошти вилучено." }
    end

    # ESG-погашення: теж вилучення з обігу, але БЕЗ `sourceable` — і саме ця
    # відсутність робила стару деривацію хибною (`KlimaDao::RetirementService`).
    trait :esg_retirement_burn do
      direction { :burn }
      notes { "🌿 ESG Retirement via KlimaDAO" }
    end
  end
end
