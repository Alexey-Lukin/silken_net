# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "sidekiq/api"

module Api
  module V1
    # [ARCH.81] Панель, на яку дивляться під час інциденту. Кожна проба тут
    # мусить доводити те, що обіцяє її ім'я — механіка й підстава живуть в
    # одному домі, `SilkenNet::HealthProbes`, спільному з `/ready`.
    class SystemHealthController < BaseController
      before_action :authorize_admin!

      # GET /system_health
      # Стан системи: CoAP-інтейк (UDP), процеси Sidekiq, база.
      def show
        @health = {
          checked_at: Time.current.iso8601,
          coap_listener: SilkenNet::HealthProbes.coap_listener,
          sidekiq: sidekiq_status,
          database: database_status
        }

        respond_to do |format|
          format.json { render json: @health }
          format.html do
            render_dashboard(
              title: I18n.t("system_health.show_title"),
              component: SystemHealth::Show.new(health: @health)
            )
          end
        end
      end

      private

      # Живість тут — це наявність ПРОЦЕСІВ, а не відповідь Redis: `Sidekiq::Stats`
      # приходить і тоді, коли черги не дренує ніхто, тож картка з іменем
      # «Sidekiq Workers» світила б зеленим над мертвим флотом воркерів.
      def sidekiq_status
        stats = Sidekiq::Stats.new
        processes = SilkenNet::HealthProbes.sidekiq_process_count

        {
          alive: processes.positive?,
          processes: processes,
          enqueued: stats.enqueued,
          processed: stats.processed,
          failed: stats.failed,
          workers_size: stats.workers_size,
          queues: stats.queues
        }
      rescue => e
        Rails.logger.warn "[SystemHealth] Sidekiq-статистика недоступна: #{e.message}"
        { alive: false, error: "check_failed" }
      end

      def database_status
        { connected: SilkenNet::HealthProbes.database_reachable? }
      end
    end
  end
end
