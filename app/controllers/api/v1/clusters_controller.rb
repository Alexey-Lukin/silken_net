# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ClustersController < BaseController
      # Дозволяємо перегляд усім автентифікованим користувачам
      # (Інвестори бачать фінанси, Патрульні — загрози)

      # --- СПИСОК СЕКТОРІВ (The Map View / Dashboard Grid) ---
      # GET /clusters
      def index
        # Скоупимо до організації поточного користувача (Security Scope)
        # active_threats? використовує EXISTS з composite index — includes не потрібен.
        # health_index та active_trees_count — денормалізовані колонки на clusters.
        @pagy, @clusters = pagy(acting_organization!.clusters)

        respond_to do |format|
          # 1. API Response (Mobile / Externals)
          format.json do
            render json: {
              data: ClusterBlueprint.render_as_hash(@clusters),
              pagy: pagy_metadata(@pagy)
            }
          end

          # 2. Dashboard Response (Phlex + Hotwire)
          format.html do
            render_dashboard(
              title: I18n.t("clusters.index_title"),
              component: Clusters::Grid.new(clusters: @clusters, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ СЕКТОРА (The Deep Dive / Sector Matrix) ---
      # GET /clusters/:id
      def show
        @cluster = acting_organization!.clusters.find(params[:id])

        respond_to do |format|
          # 1. API Response
          format.json do
            render json: ClusterBlueprint.render_as_hash(@cluster, view: :show)
          end

          # 2. Dashboard Response
          format.html do
            # [UI.3] `.to_a` — це виконання канон-правила `04_04 §6`, а не мікро-
            # оптимізація: незавантажена relation НЕ Є «попередньо завантаженою в
            # контролері», і компонент платить ЗА КОЖНУ ідіому окремо. Виміряно на
            # цій сторінці: `@gateways` коштували ТРИ запити (`.size` → підзапит
            # COUNT, `.any?` → SELECT 1, `.each` → сам SELECT), `@recent_alerts` —
            # два. 🔴 Найпідступніша тут `.size`: її радять як безкоштовну заміну
            # `.count`, і вона такою Є — але лише на ЗАВАНТАЖЕНІЙ колекції, а цю
            # умову з місця виклику не видно.
            @gateways = @cluster.gateways.order(:uid).limit(50).to_a
            @recent_alerts = @cluster.ews_alerts.unresolved.order(created_at: :desc).limit(5).to_a
            # [UI.3] Контракт вантажить КОНТРОЛЕР — компонент його доти діставав
            # сам, усередині `initialize` (див. коментар там).
            @active_contract = @cluster.active_contract
            # [ARCH.84] Підстава під `health_index`: скільки живих дерев сектора
            # заговорило за звітну добу. Доба береться з ОДНОГО дому
            # (`AiInsight.reporting_date`, ARCH.100) — власного виразу тут бути не
            # може, інакше читач промахнеться повз запис писача, і промах ТИХИЙ.
            # `nil` = інсайту за добу немає, і тоді `health_index` теж `nil`.
            @health_insight = @cluster.ai_insights.daily_health_summary
                                      .for_date(AiInsight.reporting_date).first
            render_dashboard(
              title: I18n.t("clusters.show_title", name: @cluster.name),
              component: Clusters::Show.new(
                cluster: @cluster,
                gateways: @gateways,
                recent_alerts: @recent_alerts,
                active_contract: @active_contract,
                # [ARCH.103] ⚖️ Кластерна семантика: панель контракту друкує емісію
                # САМОГО кластера, тож субʼєкт тут відомий завжди й «не виміряно» не
                # виникає — нуль є виміром, бо агрегат виконався.
                cluster_emission: BlockchainTransaction.for_cluster(@cluster.id)
                                                       .net_minted_supply(:carbon_coin),
                health_measured: @health_insight&.measured_trees,
                health_total: @health_insight&.total_trees
              )
            )
          end
        end
      end
    end
  end
end
