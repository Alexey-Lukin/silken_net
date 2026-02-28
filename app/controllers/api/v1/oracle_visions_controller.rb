# frozen_string_literal: true

module Api
  module V1
    class OracleVisionsController < BaseController
      before_action :authorize_forester!

      # --- ПОРТФЕЛЬ ПРОГНОЗІВ ---
      # GET /api/v1/oracle_visions
      def index
        # Беремо останні стратегічні інсайти, згенеровані нашими воркерами
        @visions = AiInsight.strategic_forecasts.order(target_date: :asc).limit(10)

        render json: @visions.as_json(
          only: [ :id, :insight_type, :confidence_score, :payload, :target_date ],
          methods: [ :visual_trend_data ]
        )
      end

      # --- ЗАПУСК СИМУЛЯЦІЇ (What-If?) ---
      # POST /api/v1/oracle_visions/simulate
      # Наприклад: "Що буде, якщо температура підніметься на 5 градусів при поточному імпедансі?"
      def simulate
        # [СИНХРОНІЗОВАНО]: Використовуємо Sidekiq для важких AI-обчислень
        # Ми передаємо параметри в SimulationWorker
        job_id = SimulationWorker.perform_async(
          params[:cluster_id],
          params[:variables] # { temp_offset: +5.0, humidity_drop: -10 }
        )

        render json: {
          message: "Запит на пророцтво отримано. Оракул почав симуляцію.",
          job_id: job_id,
          status: :processing
        }, status: :accepted
      end

      # --- ЖИВИЙ ПОТІК ІСТИНИ (Hotwire/Turbo Support) ---
      # GET /api/v1/oracle_visions/stream_config
      def stream_config
        @cluster = Cluster.find(params[:cluster_id])

        # Повертаємо дані для Stimulus-контролера, щоб він знав,
        # на який канал TurboStream підписатися для отримання "живих" прогнозів
        render json: {
          stream_name: "oracle_visions_cluster_#{@cluster.id}",
          auth_token: current_user.generate_token_for(:stream_access)
        }
      end
    end
  end
end
