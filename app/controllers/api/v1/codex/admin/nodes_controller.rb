# frozen_string_literal: true

module Api
  module V1
    module Codex
      module Admin
        # Phase 6 — DAO Node CRUD surface (`/api/v1/codex/admin/nodes`).
        #
        # End-users read Nodes through the public `Codex::NodesController`;
        # this controller exists for moderators / DAO operators who need to
        # toggle `published_at`, fix translations, or onboard new lore not
        # bundled in the Atlas Foundation seed.
        #
        # Authorization is delegated to `Codex::Admin::NodePolicy`:
        #   * index/show/update → admin+
        #   * create/destroy    → super_admin only (mint/retire is rare,
        #                         and rolls a new `seed_origin = "dao"` row)
        class NodesController < BaseController
          before_action :set_node, only: [ :show, :update, :destroy ]

          # GET /api/v1/codex/admin/nodes
          def index
            authorize ::Codex::Node, policy_class: ::Codex::Admin::NodePolicy
            scope = policy_scope(::Codex::Node, policy_scope_class: ::Codex::Admin::NodePolicy::Scope)
                      .includes(:realm)
                      .order(:codex_realm_id, :id)
            render json: { data: ::Codex::NodeBlueprint.render_as_hash(scope) }
          end

          # GET /api/v1/codex/admin/nodes/:slug
          def show
            authorize @node, policy_class: ::Codex::Admin::NodePolicy
            render json: { data: ::Codex::NodeBlueprint.render_as_hash(@node, view: :show) }
          end

          # POST /api/v1/codex/admin/nodes  — super_admin only
          def create
            authorize ::Codex::Node, policy_class: ::Codex::Admin::NodePolicy
            node = ::Codex::Node.new(node_params.merge(seed_origin: :dao_proposal))

            if node.save
              render json: { data: ::Codex::NodeBlueprint.render_as_hash(node, view: :show) },
                     status: :created
            else
              render json: { errors: node.errors.full_messages }, status: :unprocessable_content
            end
          end

          # PATCH/PUT /api/v1/codex/admin/nodes/:slug
          def update
            authorize @node, policy_class: ::Codex::Admin::NodePolicy

            if @node.update(node_params)
              render json: { data: ::Codex::NodeBlueprint.render_as_hash(@node, view: :show) }
            else
              render json: { errors: @node.errors.full_messages }, status: :unprocessable_content
            end
          rescue ArgumentError => e
            # Rails 8 enums raise `ArgumentError` when an invalid value is
            # assigned (e.g. `lifecycle_status: "imaginary"`). Convert to a
            # proper 422 instead of the generic 500.
            render json: { errors: [ e.message ] }, status: :unprocessable_content
          end

          # DELETE /api/v1/codex/admin/nodes/:slug — super_admin only
          def destroy
            authorize @node, policy_class: ::Codex::Admin::NodePolicy
            @node.destroy!
            head :no_content
          end

          private

          def set_node
            @node = ::Codex::Node.find_by!(slug: params[:slug])
          end

          # Tightly scoped permitted attributes — we never accept FK ids
          # other than `realm_id`, never accept counter caches, and never
          # accept `seed_origin` (set server-side on create, immutable on
          # update so DAO rows can't be back-dated to "atlas").
          def node_params
            permitted = params.require(:node).permit(
              :slug, :codex_uid, :codex_realm_id,
              :title_uk, :title_en, :subtitle_uk, :subtitle_en,
              :archetype_key, :lifecycle_status,
              :context_md, :cyber_meaning_md, :lore_md,
              :geo_region, :latitude, :longitude,
              :discoverable_after_minutes,
              :published_at
            )
            # `external_refs` is JSONB validated by `Codex::Node#external_refs_must_be_array_of_links`.
            # Convert nested ActionController::Parameters back to plain Hash so the validator's
            # `r.is_a?(Hash)` check passes — otherwise JSON-shaped refs round-trip through strong
            # params as ACP and trip a 422 the caller can't predict.
            # `params[:node]` is guaranteed present here: `params.require(:node)`
            # two lines above already raised `ActionController::ParameterMissing`
            # (→ 400 via BaseController) if it were absent.
            if params[:node].key?(:external_refs)
              raw = params[:node][:external_refs]
              permitted[:external_refs] =
                if raw.is_a?(Array)
                  raw.map { |r| r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r }
                else
                  raw
                end
            end
            permitted
          end
        end
      end
    end
  end
end
