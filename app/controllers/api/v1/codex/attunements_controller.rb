# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # POST   /codex/nodes/:slug/attunements        — toggle ON
      # DELETE /codex/nodes/:slug/attunements/me     — toggle OFF
      #
      # Idempotent by design: re-POSTing for an existing pair updates only
      # the supplied attributes (intensity/quote) and never duplicates the
      # row, thanks to the UNIQUE (user_id, codex_node_id) DB constraint.
      class AttunementsController < BaseController
        before_action :set_node

        def create
          attrs = attunement_params
          authorize ::Codex::Attunement.new(
            user_id: current_user.id, codex_node_id: @node.id
          )

          attunement = ::Codex::Attunement
                         .find_or_initialize_by(user_id: current_user.id, codex_node_id: @node.id)
          attunement.intensity = attrs[:intensity] if attrs[:intensity].present?
          attunement.quote     = attrs[:quote]     if attrs.key?(:quote)
          attunement.intensity ||= 3

          if attunement.save
            enqueue_discovery_probe(attunement)
            respond_to do |format|
              format.json do
                render json: { data: ::Codex::AttunementBlueprint.render_as_hash(attunement) },
                       status: :created
              end
              format.html do
                redirect_to codex_node_path(@node.slug),
                            notice: I18n.t("flash.codex.attunement_saved")
              end
            end
          else
            render_validation(attunement)
          end
        end

        def destroy
          attunement = ::Codex::Attunement.find_by(user_id: current_user.id, codex_node_id: @node.id)
          if attunement
            authorize attunement, :destroy?
            attunement.destroy
          end

          respond_to do |format|
            format.json { head :no_content }
            # 303, не 302: fetch конвертує 301/302 у GET лише для POST, а DELETE
            # зберігає — тобто браузер перевидав би DELETE на сторінку вузла, де
            # такого маршруту немає. Симптом найпідступніший з можливих: привʼязку
            # знято, а користувач бачить помилку.
            format.html do
              redirect_to codex_node_path(@node.slug),
                          status: :see_other,
                          notice: I18n.t("flash.codex.attunement_removed")
            end
          end
        end

        private

        def set_node
          @node = ::Codex::Node.find_by!(slug: params[:node_slug])
        end

        def attunement_params
          # `permit` returns a strong-params hash; cast to a regular hash
          # so `key?(:quote)` works correctly when the client wants to
          # explicitly clear the quote with `quote: nil`.
          params.fetch(:attunement, {}).permit(:intensity, :quote).to_h.symbolize_keys
        end

        def render_validation(record)
          render json: { errors: record.errors.full_messages },
                 status: :unprocessable_content
        end

        # Phase 6 cross-domain stitch — every successful attune fans out
        # a Discovery probe so the `attunement_streak_days` rule can fire
        # the moment the user crosses N consecutive days. Fail-open: a
        # Sidekiq enqueue hiccup must never roll back the attune.
        def enqueue_discovery_probe(attunement)
          return unless defined?(::Codex::DiscoveryProbeWorker)

          ::Codex::DiscoveryProbeWorker.perform_async(
            attunement.user_id,
            "attunement_streak",
            {
              "codex_node_id"    => attunement.codex_node_id,
              "trigger_ref_type" => "Codex::Attunement",
              "trigger_ref_id"   => attunement.id
            }
          )
        rescue StandardError => e
          Rails.logger.warn "[Codex::AttunementsController] probe enqueue failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
