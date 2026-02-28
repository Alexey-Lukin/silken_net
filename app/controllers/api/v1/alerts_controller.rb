# frozen_string_literal: true

module Api
  module V1
    class AlertsController < BaseController
      # --- СТРІЧКА ТРИВОГ (The Real-Time Pulse) ---
      # GET /api/v1/alerts
      # Параметри: ?status=active&severity=critical&cluster_id=5
      def index
        @alerts = EwsAlert.includes(:cluster, :tree)
                          .order(created_at: :desc)

        # Фільтрація за станом (за замовчуванням — активні)
        @alerts = @alerts.where(status: params[:status] || :active)
        @alerts = @alerts.where(severity: params[:severity]) if params[:severity].present?
        @alerts = @alerts.where(cluster_id: params[:cluster_id]) if params[:cluster_id].present?

        # Пагінація: тільки останні 50 для швидкості реакції
        @alerts = @alerts.limit(50)

        render json: @alerts.as_json(
          include: {
            cluster: { only: [ :id, :name ] },
            tree: { only: [ :id, :did, :latitude, :longitude ] }
          },
          methods: [ :coordinates, :actionable? ]
        )
      end

      # --- ДЕТАЛІ ІНЦИДЕНТУ ---
      # GET /api/v1/alerts/:id
      def show
        @alert = EwsAlert.find(params[:id])
        render json: @alert
      end

      # --- РИТУАЛ ЗАКРИТТЯ (The Resolution) ---
      # PATCH /api/v1/alerts/:id/resolve
      def resolve
        @alert = EwsAlert.find(params[:id])

        # Використовуємо метод моделі, який ми зашліфували раніше
        if @alert.resolve!(user: current_user, notes: params[:notes])
          render json: {
            message: "Тривогу ##{@alert.id} втихомирено.",
            alert: @alert
          }, status: :ok
        else
          render json: { error: "Не вдалося закрити тривогу." }, status: :unprocessable_entity
        end
      end
    end
  end
end
