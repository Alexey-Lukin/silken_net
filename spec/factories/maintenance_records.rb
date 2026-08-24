# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :maintenance_record do
    association :user
    association :maintainable, factory: :tree
    action_type       { :inspection }
    performed_at      { 1.hour.ago }
    notes             { "Routine inspection of the node completed successfully." }
    labor_hours       { nil }
    parts_cost        { nil }
    hardware_verified { false }
    latitude          { nil }
    longitude         { nil }

    trait :with_gps do
      latitude  { 49.4285 }
      longitude { 32.0620 }
    end

    trait :with_cost do
      labor_hours { 2.5 }
      parts_cost  { 150.00 }
    end

    trait :hardware_verified do
      hardware_verified { true }
    end

    trait :repair do
      action_type { :repair }
      notes       { "Replaced the LoRa module and re-soldered anchor connectors." }
    end

    trait :installation do
      action_type { :installation }
      notes       { "Installed new titanium anchor and LoRa sensor unit on node." }
    end

    # [E.20] Фотодоказ. Споживачів ТРИ, і межі в них РІЗНІ — плутати їх дорого:
    #   • `evidence_backed?`  — repair/installation, валідація на КОЖЕН save;
    #   • `photo_required_for_biomass_claim` — biomass, валідація `on: :create`
    #     (⛔ every-save форма вбила б Puro-тракт: обидва воркери роблять `update!`);
    #   • `evidence_locked?`  — замок на видалення (усі три типи).
    # ⚠️ Цей коментар до 2026-08-24 стверджував, що на моделі гейта для biomass
    # ⛔ немає взагалі — присуд founder-а того ж дня зробив його хибним.
    trait :with_evidence do
      after(:build) do |record|
        record.photos.attach(
          io: StringIO.new("evidence"), filename: "evidence.jpg", content_type: "image/jpeg"
        )
      end
    end

    # [E.20] «Атестатор ≠ бенефіціар»: асоціація створює ОКРЕМОГО користувача, тож
    # інваріант «підписант ≠ автор» тримається фабрикою за побудовою, а не збігом.
    trait :attested do
      association :attestor, factory: [ :user, :forester ]
      attested_at { 1.hour.ago }
    end

    trait :biomass_extraction do
      action_type      { :biomass_extraction }
      notes            { "Extracted dead wood biomass for Puro.earth Biochar CORC certification." }
      biomass_yield_kg { 125.50 }
    end
  end
end
