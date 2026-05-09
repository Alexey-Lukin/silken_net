# frozen_string_literal: true

module Api
  module V1
    module Codex
      class NodesController < BaseController
        # GET /api/v1/codex/nodes
        # Filters: ?realm=ecosystem&lifecycle_status=thriving&q=foo&archetype=cold_wallet
        def index
          scope = policy_scope(::Codex::Node)
                    .for_realm(params[:realm])
                    .by_lifecycle(params[:lifecycle_status])
                    .by_archetype(params[:archetype])
                    .search_title(params[:q])
                    .ordered_by_elo
                    .includes(:realm)

          @pagy, @nodes = pagy(scope, limit: 21)

          respond_to do |format|
            format.json do
              render json: {
                data: ::Codex::NodeBlueprint.render_as_hash(@nodes),
                pagy: pagy_metadata(@pagy)
              }
            end
            format.html do
              realms = ::Codex::Realm.ordered.to_a
              render_dashboard(
                title: "Codex Atlas",
                component: ::Codex::Index.new(
                  nodes: @nodes,
                  pagy: @pagy,
                  realms: realms,
                  active_realm_slug: params[:realm].presence
                )
              )
            end
          end
        end

        # GET /api/v1/codex/nodes/:slug
        def show
          @node = policy_scope(::Codex::Node).find_by!(slug: params[:slug])
          authorize @node
          # Atomic-ish view counter; safe under concurrent reads.
          ::Codex::Node.where(id: @node.id).update_all("view_count = view_count + 1")

          respond_to do |format|
            format.json do
              render json: ::Codex::NodeBlueprint.render_as_hash(@node, view: :show)
            end
            format.html do
              comments = policy_scope(::Codex::Comment)
                           .where(commentable_type: "Codex::Node", commentable_id: @node.id)
                           .top_level
                           .chronological
                           .includes(:user)
                           .last(50)
              attuned = ::Codex::Attunement
                          .exists?(user_id: current_user&.id, codex_node_id: @node.id)

              render_dashboard(
                title: "Codex · #{@node.title}",
                component: ::Codex::Show.new(
                  node: @node,
                  current_user: current_user,
                  comments: comments,
                  current_user_attuned: attuned
                )
              )
            end
          end
        end
      end
    end
  end
end
