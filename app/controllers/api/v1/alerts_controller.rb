# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class AlertsController < BaseController
      before_action :set_alert, only: [ :show, :resolve ]
      # [SEC]: resolve = операційна дія (закрити бойову тривогу пожежі/tamper) —
      # лише forester+. EwsAlertPolicy#resolve? декларував саме цей намір, але
      # контролер його не викликав, тож investor (read-only роль) міг гасити
      # активну EWS-тривогу.
      before_action :authorize_forester!, only: :resolve

      # GET /api/v1/alerts
      def index
        @alerts = acting_organization!.ews_alerts
                              .includes(:cluster, :tree)
                              .order(created_at: :desc)

        # Фільтрація — параметри клієнта обмежуємо до enum-словника моделі,
        # інакше довільна строка ламає AR PG::InvalidTextRepresentation
        # та поглинає Sentry events. .keys повертає коректний whitelist.
        status_param = params[:status].presence&.to_s || "active"
        if EwsAlert.statuses.key?(status_param)
          @alerts = @alerts.where(status: status_param)
        else
          render json: { error: I18n.t("flash.alerts.invalid_status", value: status_param) }, status: :bad_request
          return
        end

        if params[:severity].present?
          severity_param = params[:severity].to_s
          unless EwsAlert.severities.key?(severity_param)
            render json: { error: I18n.t("flash.alerts.invalid_severity", value: severity_param) }, status: :bad_request
            return
          end
          @alerts = @alerts.where(severity: severity_param)
        end

        @alerts = @alerts.where(cluster_id: params[:cluster_id]) if params[:cluster_id].present?

        @pagy, @alerts = pagy(@alerts)

        respond_to do |format|
          format.json do
            render json: {
              data: @alerts.as_json(
                include: {
                  cluster: { only: [ :id, :name ] },
                  tree: { only: [ :id, :did, :latitude, :longitude ] }
                },
                methods: [ :coordinates, :actionable? ]
              ),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("alerts.index_title"),
              component: Alerts::Index.new(alerts: @alerts, pagy: @pagy, organization: acting_organization!)
            )
          end
        end
      end

      # GET /api/v1/alerts/:id
      def show
        respond_to do |format|
          format.json do
            render json: {
              data: @alert.as_json(
                include: {
                  cluster: { only: [ :id, :name ] },
                  tree: { only: [ :id, :did, :latitude, :longitude ] }
                },
                methods: [ :coordinates, :actionable? ]
              )
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("alerts.show_title", id: @alert.id),
              component: Alerts::Row.new(alert: @alert)
            )
          end
        end
      end

      # PATCH /api/v1/alerts/:id/resolve
      def resolve
        if @alert.resolve!(user: current_user, notes: params[:notes])
          respond_to do |format|
            format.json { render json: { message: I18n.t("flash.alerts.acknowledged", id: @alert.id), alert: @alert } }
            format.turbo_stream do
              # `dom_id`, а НЕ рукописний `alert_#{id}`: рядок рендериться як
              # `ews_alert_{id}`, тож стара ціль не існувала в жодній сторінці
              # застосунку і replace був тихим no-op. UX тримався виключно на
              # асинхронному броадкасті, у якого 5-секундний тротл — тобто при
              # збігу оператор не бачив нічого й тиснув «Вирішити» вдруге,
              # дістаючи вже відмову AASM.
              render turbo_stream: turbo_stream.replace(
                ActionView::RecordIdentifier.dom_id(@alert),
                Alerts::Row.new(alert: @alert).call
              )
            end
            format.html { redirect_to api_v1_alerts_path, notice: I18n.t("flash.alerts.resolved") }
          end
        else
          render_validation_error(@alert)
        end
      end

      private

      def set_alert
        @alert = acting_organization!.ews_alerts.find(params[:id])
      end
    end
  end
end
