# frozen_string_literal: true

module Codex
  class DiscoveryBlueprint < Blueprinter::Base
    identifier :id

    fields :user_id, :codex_node_id, :trigger_type,
           :trigger_ref_type, :trigger_ref_id, :unlocked_at, :created_at

    field :node_slug do |d|
      d.node&.slug
    end
    field :node_title_en do |d|
      d.node&.title_en
    end
    field :node_title_uk do |d|
      d.node&.title_uk
    end
    field :node_archetype_key do |d|
      d.node&.archetype_key
    end
  end
end
