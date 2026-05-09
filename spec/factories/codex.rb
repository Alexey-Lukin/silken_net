# frozen_string_literal: true

FactoryBot.define do
  factory :codex_realm, class: "Codex::Realm" do
    sequence(:slug) { |n| "realm_#{n}" }
    name_uk { "Тестовий Реалм" }
    name_en { "Test Realm" }
    glyph { "forest" }
    accent_token { "gaia-primary" }
    sequence(:position)
    is_active { true }
  end

  factory :codex_node, class: "Codex::Node" do
    association :realm, factory: :codex_realm
    sequence(:slug) { |n| "node-#{n}" }
    sequence(:codex_uid) { |n| format("CDX-ECO-%04d", n) }
    title_uk { "Тестовий Архетип" }
    title_en { "Test Archetype" }
    archetype_key { Codex::ARCHETYPES.first }
    lifecycle_status { :unknown }
    seed_origin { :seed }
    external_refs { [] }
    published_at { Time.current }

    trait :thriving do
      lifecycle_status { :thriving }
    end

    trait :with_geo do
      latitude  { 49.4444 }
      longitude { 31.9889 }
      geo_region { "cherkasy-bir" }
    end

    trait :with_lore do
      context_md       { "**Context** with [link](https://example.com)." }
      cyber_meaning_md { "Cyber meaning paragraph." }
      lore_md          { "Mythic lore paragraph." }
    end
  end

  factory :codex_citation, class: "Codex::Citation" do
    association :node, factory: :codex_node
    association :created_by_user, factory: :user
    citable_type { "Tree" }
    sequence(:citable_id)
    note { "Cited from a maintenance run." }
  end
end
