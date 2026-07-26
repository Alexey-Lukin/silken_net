# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # `Codex::Match` is the resource (a single Battle Arena duel). REST
      # actions:
      #   GET  /api/v1/codex/matches/new   → Turbo Frame Arena with the next pair
      #   POST /api/v1/codex/matches       → record vote / skip
      #
      # The "Battle Arena" naming is preserved at the UX layer (Phlex
      # `Codex::Battle::Arena` component) — it's a UI label, not a REST noun.
      #
      # Both actions route through `Codex::MatchPolicy` (auth required).
      # Rack::Attack rule: 60 POSTs / 1 minute / actor — see
      # `config/initializers/rack_attack.rb` (`codex/matches/create`).
      class MatchesController < BaseController
        def new
          authorize ::Codex::Match.new(user_id: current_user.id), :create?

          realm = resolve_realm(params[:realm])
          result = ::Codex::PairSelectorService.call(user: current_user, realm: realm)

          unless result.success?
            return render_dashboard(
              title: I18n.t("codex.battle_arena.page_title", default: "Codex · Battle Arena"),
              component: ::Codex::Battle::Arena.new(
                left: nil, right: nil, pair_seed: nil,
                realm: realm, error: result.error
              ),
              status: :unprocessable_content
            )
          end

          render_dashboard(
            title: I18n.t("codex.battle_arena.page_title", default: "Codex · Battle Arena"),
            component: ::Codex::Battle::Arena.new(
              left: result.left, right: result.right,
              pair_seed: result.pair_seed, realm: result.realm,
              error: nil
            )
          )
        end

        def create
          authorize ::Codex::Match.new(user_id: current_user.id), :create?

          pair_seed   = params[:pair_seed].to_s.strip
          winner_slug = params[:winner_slug].presence
          skip        = ActiveModel::Type::Boolean.new.cast(params[:skip])

          result = ::Codex::VoteRecorderService.call(
            user: current_user,
            pair_seed: pair_seed,
            winner_slug: winner_slug,
            skip: skip
          )

          if result.success?
            respond_to do |format|
              format.json do
                render json: { data: ::Codex::MatchBlueprint.render_as_hash(result.match) },
                       status: :created
              end
              format.html do
                # Echo a fresh Arena frame so Turbo can swap the next pair
                # without a full reload. Fall back to an error state if the
                # selector cannot produce a new pair (e.g. realm exhausted).
                next_pair = ::Codex::PairSelectorService.call(
                  user: current_user, realm: result.match.realm
                )
                render_dashboard(
                  title: I18n.t("codex.battle_arena.page_title", default: "Codex · Battle Arena"),
                  component: ::Codex::Battle::Arena.new(
                    left: next_pair.success? ? next_pair.left  : nil,
                    right: next_pair.success? ? next_pair.right : nil,
                    pair_seed: next_pair.success? ? next_pair.pair_seed : nil,
                    realm: next_pair.realm || result.match.realm,
                    error: next_pair.success? ? nil : next_pair.error
                  ),
                  status: :created
                )
              end
            end
          else
            status = result.error == "seed_invalid_or_consumed" ? :forbidden : :unprocessable_content
            render json: { error: result.error }, status: status
          end
        end

        private

        def resolve_realm(slug)
          return ::Codex::Realm.ordered.first if slug.blank?

          ::Codex::Realm.find_by(slug: slug) || ::Codex::Realm.ordered.first
        end
      end
    end
  end
end
