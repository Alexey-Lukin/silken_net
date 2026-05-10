# frozen_string_literal: true

module Codex
  class FractionBlueprint < Blueprinter::Base
    identifier :id

    fields :codex_node_id, :archetype_key, :house_color_token,
           :chosen_at, :last_changed_at

    field :user_id
    field :node_slug do |fraction|
      fraction.node&.slug
    end
    field :node_title_uk do |fraction|
      fraction.node&.title_uk
    end
    field :node_title_en do |fraction|
      fraction.node&.title_en
    end
    field :realm_slug do |fraction|
      fraction.node&.realm&.slug
    end
    field :cooldown_until do |fraction|
      fraction.cooldown_until.iso8601
    end
    field :cooldown_active do |fraction|
      fraction.cooldown_active?
    end
  end
end
