# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # GET /codex/discoveries/me — paginated list of own unlocks.
      #
      # Routes to `#index` (RESTful: returns a *collection* scoped to the
      # current user). The `/me` path segment is a URL-level convention for
      # self-resources.
      #
      # Response:
      #   * JSON  → `{ data: [DiscoveryBlueprint, ...], meta: {pagy} }`
      #   * HTML  → fragment list (Phlex `Codex::Discoveries::List`)
      class DiscoveriesController < BaseController
        def index
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
              render_dashboard(
                title: I18n.t("codex.discoveries.page_title", default: "Codex · My Discoveries"),
                component: ::Codex::Discoveries::List.new(discoveries: @discoveries, pagy: @pagy)
              )
            end
          end
        end
      end
    end
  end
end
