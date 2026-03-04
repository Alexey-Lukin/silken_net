# frozen_string_literal: true

module Api
  module V1
    class OracleVisionsController < BaseController
      before_action :authorize_forester!
      before_action :authorize_admin!, only: [ :simulate ]

      # GET /api/v1/oracle_visions
      def index
        # Використовуємо upcoming для прогнозів, оскільки strategic_forecasts може бути відсутнім
        @visions = AiInsight.upcoming.order(target_date: :asc).limit(10)

        # [FINANCIAL ENGINE]: Розрахунок "Очікуваного врожаю" (SCC Yield)
        # Оракул обчислює потенційну емісію на наступні 24 години на основі живого пульсу лісу.
        @scc_yield = calculate_expected_yield

        respond_to do |format|
          format.json { render json: { visions: @visions, yield_forecast: @scc_yield } }
          format.html do
            render_dashboard(
              title: "Oracle Visions // Future Matrix",
              component: Views::Components::OracleVisions::Index.new(
                visions: @visions,
                yield_forecast: @scc_yield
              )
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

      private

      # 🧬 Алгоритм Кенозису для фінансового прогнозування
      def calculate_expected_yield
        # [КЕНОЗИС ОПТИМІЗАЦІЇ]: Кешуємо розрахунок на 1 годину, щоб уникнути
        # перевантаження БД при масовому запиті сторінки Dashboard.
        Rails.cache.fetch("oracle_expected_yield_24h", expires_in: 1.hour) do
          # Отримуємо поріг емісії з нашої токеноміки (напр. 10,000 балів = 1 SCC)
          threshold = TokenomicsEvaluatorWorker::EMISSION_THRESHOLD

          # [ОПТИМІЗАЦІЯ]: Використовуємо find_each для батчевої обробки замість
          # завантаження всіх дерев в оперативну пам'ять одночасно.
          total_potential = 0.0

          Tree.active.includes(:ai_insights).find_each(batch_size: 1000) do |tree|
            # sap_flow_index береться з останньої зафіксованої телеметрії
            sap_index = tree.latest_telemetry&.sap_flow || 0.0
            # current_stress - останній вердикт AI Оракула (0.0 - 1.0)
            stress = tree.current_stress

            # Чим вищий стрес, тим менша ефективність перетворення біо-енергії в капітал
            total_potential += sap_index * (1.0 - stress)
          end

          # Повертаємо очікувану кількість SCC за наступну добу
          ((total_potential * 24) / threshold).round(4)
        end
      end
    end
  end
end
