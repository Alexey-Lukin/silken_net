# frozen_string_literal: true

module Api
  module V1
    class AlertsController < BaseController
      # GET /api/v1/alerts
      def index
        @alerts = EwsAlert.includes(:cluster, :tree)
                          .order(created_at: :desc)

        # Фільтрація
        @alerts = @alerts.where(status: params[:status] || :active)
        @alerts = @alerts.where(severity: params[:severity]) if params[:severity].present?
        @alerts = @alerts.where(cluster_id: params[:cluster_id]) if params[:cluster_id].present?
        @alerts = @alerts.limit(50)

        respond_to do |format|
          format.json do
            render json: @alerts.as_json(
              include: {
                cluster: { only: [ :id, :name ] },
                tree: { only: [ :id, :did, :latitude, :longitude ] }
              },
              methods: [ :coordinates, :actionable? ]
            )
          end
          format.html do
            render_dashboard(
              title: "Alerts Command",
              component: Views::Components::Alerts::Index.new(alerts: @alerts)
            )
          end
        end
      end

      # PATCH /api/v1/alerts/:id/resolve
      def resolve
        @alert = EwsAlert.find(params[:id])

        if @alert.resolve!(user: current_user, notes: params[:notes])
          respond_to do |format|
            format.json { render json: { message: "Тривогу ##{@alert.id} втихомирено.", alert: @alert } }
            format.turbo_stream do
              # Ми миттєво замінюємо рядок у таблиці на "втихомирений" стан
              render turbo_stream: turbo_stream.replace(
                "alert_#{@alert.id}",
                Views::Components::Alerts::Row.new(alert: @alert).call
              )
            end
            format.html { redirect_to api_v1_alerts_path, notice: "Загрозу локалізовано." }
          end
        else
          render_validation_error(@alert)
        end
      end
    end
  end
end
