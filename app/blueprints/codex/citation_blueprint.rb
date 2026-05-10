# frozen_string_literal: true

module Codex
  # Citation API payload — flat shape with denormalised Node fields so
  # the renderer (Pill / Strip components, mobile clients) doesn't need
  # to re-fetch the Node by `codex_node_id`. The `note` is plain text;
  # rendering layer must HTML-escape (Phlex `plain` does this by default).
  class CitationBlueprint < Blueprinter::Base
    identifier :id

    fields :codex_node_id, :citable_type, :citable_id,
           :note, :created_by_user_id, :created_at

    field :node_slug do |c|
      c.node&.slug
    end
    field :node_title_en do |c|
      c.node&.title_en
    end
    field :node_title_uk do |c|
      c.node&.title_uk
    end
    field :node_archetype_key do |c|
      c.node&.archetype_key
    end
  end
end
