# frozen_string_literal: true

class Codex::NodeBlueprint < Blueprinter::Base
  identifier :id

  fields :slug, :codex_uid,
         :title_uk, :title_en, :subtitle_uk, :subtitle_en,
         :archetype_key,
         :lifecycle_status,
         :geo_region,
         :latitude, :longitude,
         :attunement_count, :comments_count,
         :discovery_count, :citation_count,
         :attunement_elo, :match_count,
         :seed_origin

  field(:realm_slug) { |node| node.realm&.slug }

  view :show do
    fields :context_md, :cyber_meaning_md, :lore_md, :external_refs,
           :discoverable_after_minutes, :published_at, :view_count
  end
end
