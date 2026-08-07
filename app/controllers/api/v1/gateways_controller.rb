# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class GatewaysController < BaseController
      # GET /gateways
      def index
        @pagy, @gateways = pagy(
          acting_organization!.gateways
            .includes(:cluster, :latest_gateway_telemetry_log)
        )

        respond_to do |format|
          format.json do
            render json: {
              data: GatewayBlueprint.render_as_hash(@gateways),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            # Скоуп, а не власне вікно: поріг живе в `Gateway` і деривується з
            # `config_sleep_interval_s` кожної Королеви. Хардкод «5 хвилин»
            # називав офлайном шлюз, який за конфігом спить годину.
            online_count = acting_organization!.gateways.online.count
            render_dashboard(
              title: I18n.t("gateways.index_title"),
              component: Gateways::Index.new(gateways: @gateways, pagy: @pagy, online_count: online_count)
            )
          end
        end
      end

      # GET /gateways/:id
      def show
        @gateway = acting_organization!.gateways.find(params[:id])

        respond_to do |format|
          format.json { render json: GatewayBlueprint.render_as_hash(@gateway) }
          format.html do
            @latest_log = @gateway.latest_gateway_telemetry_log
            @active_soldiers = @gateway.trees.where(status: :active).limit(200)
            render_dashboard(
              title: I18n.t("gateways.show_title", uid: @gateway.uid),
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
