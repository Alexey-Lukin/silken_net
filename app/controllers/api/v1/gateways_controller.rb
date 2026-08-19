# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class GatewaysController < BaseController
      # GET /gateways
      def index
        # [PERF.1 (а)] Преload `:latest_gateway_telemetry_log` знято: щоб узяти по
        # ОДНОМУ рядку на шлюз, він матеріалізував усю історію пульсів (`Sort` над
        # `Append` по всіх партиціях) — і робив це для ОБОХ форматів, тоді як
        # `GatewayBlueprint` цієї асоціації не віддає взагалі, тобто для JSON це
        # була чиста втрата. Останній пульс тепер тягне HTML-гілка й лише вона,
        # через `latest_per_gateway` (LATERAL + рання зупинка на індексі).
        # ⚠️ Сама асоціація ЛИШАЄТЬСЯ — `#show` бере її на ОДНОМУ шлюзі й дістає
        # добрий план (`Limit` + `Merge Append`); дефект був у кардинальності
        # СПИСКУ, не в асоціації, тож «прибрати `has_one`» зламало б здоровий сайт.
        @pagy, @gateways = pagy(acting_organization!.gateways.includes(:cluster))

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
              component: Gateways::Index.new(
                gateways: @gateways,
                pagy: @pagy,
                online_count: online_count,
                latest_logs: GatewayTelemetryLog.latest_per_gateway(@gateways.map(&:uid))
              )
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
            # [UI.3] Три властивості цього рядка несучі, і жодна не косметична.
            # `includes` — бо сітка кличе `under_threat?` на КОЖЕН вузол (до 200
            # EXISTS'ів на рендер). `.to_a` — бо компонент спершу лічить, а потім
            # ітерує ту саму колекцію: на relation це COUNT + SELECT, на масиві
            # один SELECT. І саме масив робить правдивим докстрінг компонента,
            # який роками ЗАЯВЛЯВ `Array<Tree> pre-loaded`, отримуючи relation.
            @active_soldiers = @gateway.trees.where(status: :active)
                                       .includes(:unresolved_ews_alerts).limit(200).to_a
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
