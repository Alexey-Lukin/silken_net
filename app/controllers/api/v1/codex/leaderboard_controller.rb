# frozen_string_literal: true

module Api
  module V1
    module Codex
      # GET /api/v1/codex/leaderboard?realm=<slug>&limit=<N>
      #
      # Public read-only top-N Elo board scoped to a single realm. HTML
      # response is a Phlex `Codex::Leaderboard::Table`; JSON is a thin
      # array of `{slug, title, attunement_elo, match_count, lifecycle}`.
      class LeaderboardController < BaseController
        skip_before_action :authenticate_user!, only: [ :index ]

        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        def index
          realm = resolve_realm(params[:realm])
          limit = clamp_limit(params[:limit])

          nodes = ::Codex::Node
                    .where(codex_realm_id: realm&.id)
                    .where.not(lifecycle_status: %w[destroyed extinct])
                    .order(attunement_elo: :desc, match_count: :desc, id: :asc)
                    .limit(limit)

          respond_to do |format|
            format.json do
              render json: { data: nodes.map { |n| serialize(n) } }
            end
            format.html do
              render(
                ::Codex::Leaderboard::Table.new(
                  realm: realm, nodes: nodes, limit: limit
                )
              )
            end
          end
        end

        private

        def resolve_realm(slug)
          slug.present? ? ::Codex::Realm.find_by(slug: slug) : ::Codex::Realm.ordered.first
        end

        def clamp_limit(raw)
          n = raw.to_i
          n = DEFAULT_LIMIT if n <= 0
          [ n, MAX_LIMIT ].min
        end

        def serialize(node)
          {
            slug: node.slug,
            title_uk: node.title_uk,
            title_en: node.title_en,
            attunement_elo: node.attunement_elo,
            match_count: node.match_count,
            lifecycle_status: node.lifecycle_status
          }
        end
      end
    end
  end
end
