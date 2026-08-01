# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # POST /codex/fractions          — initial pick or re-pick (idempotency-key required for JSON)
      # GET  /codex/fractions/me       — caller's current fraction (or 204 when none)
      # GET  /codex/fractions/picker?realm=… — Turbo Frame fragment with picker grid
      #
      # `GET /me` routes to `#show` (REST: a single user-singleton resource).
      # The `/me` path segment is a URL-level convention for self-resources.
      #
      # All three endpoints route through `Codex::FractionPolicy` via Pundit;
      # the cooldown gate lives in `Codex::FractionChangeService`.
      class FractionsController < BaseController
        def create
          slug = params.dig(:fraction, :node_slug) || params[:node_slug]
          node = ::Codex::Node.find_by!(slug: slug)

          authorize ::Codex::Fraction.new(user_id: current_user.id), :create?

          result = ::Codex::FractionChangeService.call(
            user: current_user, node: node
          )

          if result.success?
            respond_to do |format|
              format.json do
                render json: { data: ::Codex::FractionBlueprint.render_as_hash(result.fraction) },
                       status: :created
              end
              format.html do
                redirect_to codex_node_path(node.slug),
                            notice: "Fraction set: #{node.title_en}."
              end
            end
          elsif result.errors.include?("cooldown_active")
            respond_to do |format|
              format.json do
                render json: {
                  error: "cooldown_active",
                  cooldown_until: result.cooldown_until.iso8601,
                  fraction: ::Codex::FractionBlueprint.render_as_hash(result.fraction)
                }, status: :too_many_requests
              end
              format.html do
                redirect_to codex_node_path(node.slug),
                            alert: "Fraction cooldown active until #{result.cooldown_until.iso8601}."
              end
            end
          else
            render json: { errors: result.errors }, status: :unprocessable_content
          end
        end

        def show
          fraction = current_user.codex_fraction
          authorize fraction || ::Codex::Fraction.new(user_id: current_user.id), :show?

          respond_to do |format|
            format.json do
              if fraction
                render json: { data: ::Codex::FractionBlueprint.render_as_hash(fraction) }
              else
                head :no_content
              end
            end
            format.html do
              render_dashboard(
                title: I18n.t("codex.fractions.my_page_title", default: "Codex · My Fraction"),
                component: ::Codex::Fractions::Card.new(
                  fraction: fraction, current_user: current_user
                )
              )
            end
          end
        end

        def picker
          authorize ::Codex::Fraction.new(user_id: current_user.id), :create?

          realm_slug = params[:realm].presence
          realms = ::Codex::Realm.ordered
          active_realm = if realm_slug
            realms.find_by(slug: realm_slug) || realms.first
          else
            realms.first
          end

          nodes = ::Codex::Node
                    .where(codex_realm_id: active_realm&.id)
                    .where.not(lifecycle_status: %w[destroyed extinct])
                    .order(:title_en)
                    .limit(48)

          render_dashboard(
            title: I18n.t("codex.fractions.picker_page_title", default: "Codex · Choose a Fraction"),
            component: ::Codex::Fractions::Picker.new(
              realms: realms,
              active_realm: active_realm,
              nodes: nodes,
              current_fraction: current_user.codex_fraction
            )
          )
        end
      end
    end
  end
end
