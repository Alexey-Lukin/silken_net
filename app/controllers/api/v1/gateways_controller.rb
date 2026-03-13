# frozen_string_literal: true

module Api
  module V1
    class GatewaysController < BaseController
      # GET /api/v1/gateways
      def index
        @pagy, @gateways = pagy(
          current_user.organization.gateways
            .includes(:cluster, :latest_gateway_telemetry_log)
        )

        respond_to do |format|
          format.json do
            render json: {
              data: @gateways,
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            online_count = current_user.organization.gateways
                             .where("last_seen_at > ?", 5.minutes.ago).count
            render_dashboard(
              title: "Queen Registry",
              component: Gateways::Index.new(gateways: @gateways, pagy: @pagy, online_count: online_count)
            )
          end
        end
      end

      # GET /api/v1/gateways/:id
      def show
        @gateway = current_user.organization.gateways.find(params[:id])

        respond_to do |format|
          format.json { render json: @gateway }
          format.html do
            @latest_log = @gateway.latest_gateway_telemetry_log
            @active_soldiers = @gateway.trees.where(status: :active).limit(200)
            render_dashboard(
              title: "Queen // #{@gateway.uid}",
              component: Gateways::Show.new(
                gateway: @gateway,
                latest_log: @latest_log,
                active_soldiers: @active_soldiers
              )
            )
          end
        end
      end
    end
  end
end
