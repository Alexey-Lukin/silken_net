# frozen_string_literal: true

module Api
  module V1
    module Codex
      # GET /api/v1/codex/discoveries/me — paginated list of own unlocks.
      #
      # Response:
      #   * JSON  → `{ data: [DiscoveryBlueprint, ...], meta: {pagy} }`
      #   * HTML  → fragment list (Phlex `Codex::Discoveries::List`)
      class DiscoveriesController < BaseController
        def me
          authorize ::Codex::Discovery, :index?

          scope = policy_scope(::Codex::Discovery).includes(:node).recent
          @pagy, @discoveries = pagy(scope, limit: 21)

          respond_to do |format|
            format.json do
              render json: {
                data: ::Codex::DiscoveryBlueprint.render_as_hash(@discoveries),
                meta: {
                  count: @pagy.count,
                  page:  @pagy.page,
                  pages: @pagy.pages
                }
              }
            end
            format.html do
              render(::Codex::Discoveries::List.new(discoveries: @discoveries, pagy: @pagy))
            end
          end
        end
      end
    end
  end
end
