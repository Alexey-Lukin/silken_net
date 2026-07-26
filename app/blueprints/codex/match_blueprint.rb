# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Codex
  class MatchBlueprint < Blueprinter::Base
    identifier :id

    fields :codex_realm_id, :left_node_id, :right_node_id, :winner_node_id,
           :pair_seed, :elo_delta_left, :elo_delta_right, :created_at

    field :user_id
    field :is_skip do |match|
      match.skip?
    end
    field :winner_slug do |match|
      match.winner_node&.slug
    end
  end
end
