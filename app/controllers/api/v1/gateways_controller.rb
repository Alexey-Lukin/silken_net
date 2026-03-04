# frozen_string_literal: true

module Api
  module V1
    class GatewaysController < BaseController
      # GET /api/v1/gateways
      def index
        @gateways = current_user.organization.gateways
                      .includes(:cluster, :latest_gateway_telemetry_log)

        respond_to do |format|
          format.json { render json: @gateways }
          format.html do
            render_dashboard(
              title: "Queen Registry",
              component: Views::Components::Gateways::Index.new(gateways: @gateways)
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
            render_dashboard(
              title: "Queen // #{@gateway.uid}",
              component: Views::Components::Gateways::Show.new(gateway: @gateway)
            )
          end
        end
      end
    end
  end
end
