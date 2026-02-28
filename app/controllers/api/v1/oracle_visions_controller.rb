# frozen_string_literal: true

module Api
  module V1
    class OracleVisionsController < BaseController
      before_action :authorize_forester!

      # GET /api/v1/oracle_visions
      def index
        @visions = AiInsight.strategic_forecasts.order(target_date: :asc).limit(10)

        respond_to do |format|
          format.json { render json: @visions }
          format.html do
            render_dashboard(
              title: "Oracle Visions // Future Matrix",
              component: Views::Components::OracleVisions::Index.new(visions: @visions)
            )
          end
        end
      end

      # --- ПОВЕРНЕНО: Конфігурація для зовнішніх стрімів ---
      # GET /api/v1/oracle_visions/stream_config?cluster_id=5
      def stream_config
        @cluster = Cluster.find(params[:cluster_id])

        render json: {
          stream_name: "oracle_visions_cluster_#{@cluster.id}",
          # Використовуємо вбудований у Rails 8 механізм підпису токенів
          auth_token: current_user.generate_token_for(:stream_access),
          provider: "SolidCable" 
        }
      end

      # POST /api/v1/oracle_visions/simulate
      def simulate
        job_id = SimulationWorker.perform_async(params[:cluster_id], params[:variables])

        render json: {
          message: "Оракул почав симуляцію.",
          job_id: job_id
        }, status: :accepted
      end
    end
  end
end
