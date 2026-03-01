# frozen_string_literal: true

module Api
  module V1
    class GatewaysController < BaseController
      # GET /api/v1/gateways
      def index
        @gateways = Gateway.includes(:cluster, :trees, :gateway_telemetry_logs).all

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
        @gateway = Gateway.find(params[:id])

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
