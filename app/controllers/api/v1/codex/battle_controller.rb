# frozen_string_literal: true

module Api
  module V1
    module Codex
      # GET  /api/v1/codex/battle/pair?realm=<slug>  → Turbo Frame Arena
      # POST /api/v1/codex/battle/votes              → record vote / skip
      #
      # Both endpoints route through `Codex::MatchPolicy` (auth required).
      # Vote-rate Rack::Attack rule: 60 / 1 minute / actor.
      class BattleController < BaseController
        def pair
          authorize ::Codex::Match.new(user_id: current_user.id), :create?

          realm = resolve_realm(params[:realm])
          result = ::Codex::PairSelectorService.call(user: current_user, realm: realm)

          unless result.success?
            return render(
              ::Codex::Battle::Arena.new(
                left: nil, right: nil, pair_seed: nil,
                realm: realm, error: result.error
              ),
              status: :unprocessable_entity
            )
          end

          render(
            ::Codex::Battle::Arena.new(
              left: result.left, right: result.right,
              pair_seed: result.pair_seed, realm: result.realm,
              error: nil
            )
          )
        end

        def vote
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
                # Echo a fresh Arena frame so the Stimulus client can
                # turbo-stream the next pair without a full reload.
                next_pair = ::Codex::PairSelectorService.call(
                  user: current_user, realm: result.match.realm
                )
                render(
                  ::Codex::Battle::Arena.new(
                    left: next_pair.left, right: next_pair.right,
                    pair_seed: next_pair.pair_seed, realm: next_pair.realm,
                    error: nil
                  ),
                  status: :created
                )
              end
            end
          else
            status = result.error == "seed_invalid_or_consumed" ? :forbidden : :unprocessable_entity
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
