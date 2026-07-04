# frozen_string_literal: true

module Api
  module V1
    class OracleVisionsController < BaseController
      before_action :authorize_forester!
      before_action :authorize_admin!, only: [ :simulate ]

      # GET /api/v1/oracle_visions
      def index
        org = current_user.organization

        # Використовуємо upcoming для прогнозів, оскільки strategic_forecasts може бути відсутнім.
        # [SCOPE FIX]: Раніше повертали глобальні AiInsight — інвестор з org A
        # бачив прогнози для org B. AiInsight зберігає прив'язку через polymorphic
        # `analyzable` (Cluster / Tree / Organization), а не через колонку
        # `cluster_id` (її немає в схемі ai_insights — див. `db/structure.sql`).
        # Тому фільтруємо по всіх трьох типах analyzable.
        @visions = scope_visions_for(org).upcoming.order(target_date: :asc).limit(10)

        # [FINANCIAL ENGINE]: Розрахунок "Очікуваного врожаю" (SCC Yield)
        # Оракул обчислює потенційну емісію на наступні 24 години на основі живого пульсу лісу.
        @scc_yield = calculate_expected_yield(org)

        respond_to do |format|
          format.json { render json: { visions: @visions, yield_forecast: @scc_yield } }
          format.html do
            @clusters = current_user.organization.clusters.order(:name)
            render_dashboard(
              title: "Oracle Visions // Future Matrix",
              component: OracleVisions::Index.new(
                visions: @visions,
                yield_forecast: @scc_yield,
                clusters: @clusters
              )
            )
          end
        end
      end

      # --- ПОВЕРНЕНО: Конфігурація для зовнішніх стрімів ---
      # GET /api/v1/oracle_visions/stream_config?cluster_id=5
      def stream_config
        @cluster = current_user.organization.clusters.find(params[:cluster_id])

        render json: {
          stream_name: "oracle_visions_cluster_#{@cluster.id}",
          # Використовуємо вбудований у Rails 8 механізм підпису токенів
          auth_token: current_user.generate_token_for(:stream_access),
          provider: "SolidCable"
        }
      end

      # POST /api/v1/oracle_visions/simulate
      def simulate
        # [TENANT-ISOLATION]: cluster_id must belong to the caller's organization.
        # SimulationWorker walks Trees by cluster_id without re-checking org, so an
        # unguarded admin from org A could trigger a simulation against org B's
        # cluster. `find` raises ActiveRecord::RecordNotFound which BaseController
        # renders as 404 — keeping the response shape identical to other IDOR
        # guards (e.g. firmware deploy, stream_config).
        cluster = current_user.organization.clusters.find(params[:cluster_id])

        permitted_variables = params.permit(variables: [ :sigma, :rho, :beta ])[:variables]
        job_id = SimulationWorker.perform_async(cluster.id, permitted_variables&.to_h)

        render json: {
          message: I18n.t("flash.oracle.simulation_started"),
          job_id: job_id
        }, status: :accepted
      end

      private

      # Polymorphic scope: an AiInsight belongs to this org when its analyzable
      # is one of the org's Clusters, an org-owned Tree, or the Organization
      # row itself. Returning an ActiveRecord::Relation lets callers chain
      # additional scopes (`upcoming`, `order`, `limit`).
      def scope_visions_for(org)
        cluster_ids = org.clusters.select(:id)
        tree_ids = Tree.where(cluster_id: cluster_ids).select(:id)

        AiInsight.where(
          "(analyzable_type = 'Cluster' AND analyzable_id IN (?)) OR " \
          "(analyzable_type = 'Tree' AND analyzable_id IN (?)) OR " \
          "(analyzable_type = 'Organization' AND analyzable_id = ?)",
          cluster_ids, tree_ids, org.id
        )
      end

      # 🧬 Алгоритм Кенозису для фінансового прогнозування
      # [TENANT-ISOLATION FIX]: Cache key per-org. Previously a single global
      # key (`oracle_expected_yield_24h`) leaked the protocol-wide total across
      # tenants — an investor at org A would see org B's yield. Cache is now
      # keyed by org id; the inner Tree scope is also restricted to the org.
      def calculate_expected_yield(org)
        Rails.cache.fetch("oracle_expected_yield_24h_org_#{org.id}", expires_in: 1.hour) do
          threshold = TokenomicsEvaluatorWorker.emission_threshold
          total_potential = 0.0

          org.trees.active.includes(:ai_insights).find_each(batch_size: 1000) do |tree|
            sap_index = tree.latest_telemetry_log&.sap_flow || 0.0
            stress = tree.current_stress
            total_potential += sap_index * (1.0 - stress)
          end

          ((total_potential * 24) / threshold).round(4)
        end
      end
    end
  end
end
