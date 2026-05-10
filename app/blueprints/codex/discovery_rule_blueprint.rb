# frozen_string_literal: true

module Codex
  class DiscoveryRuleBlueprint < Blueprinter::Base
    identifier :id

    fields :name, :codex_node_id, :condition_type, :threshold_value,
           :params, :active, :created_by_user_id, :created_at, :updated_at

    field :node_slug do |r|
      r.node&.slug
    end
  end
end
