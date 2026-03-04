# frozen_string_literal: true

module Api
  module V1
    class SystemHealthController < BaseController
      before_action :authorize_admin!

      # GET /api/v1/system_health
      # Моніторинг стану системи: CoAP listener, Sidekiq, UDP
      def show
        @health = {
          checked_at: Time.current.iso8601,
          coap_listener: coap_status,
          sidekiq: sidekiq_status,
          database: database_status
        }

        respond_to do |format|
          format.json { render json: @health }
          format.html do
            render_dashboard(
              title: "System Health",
              component: Views::Components::SystemHealth::Show.new(health: @health)
            )
          end
        end
      end

      private

      # Перевірка статусу CoAP listener (UDP-сервіс на порту 5683)
      def coap_status
        port = ENV.fetch("COAP_PORT", 5683).to_i
        alive = port_open?("127.0.0.1", port)

        { alive: alive, port: port }
      rescue => e
        { alive: false, port: port, error: e.message }
      end

      # Статистика черг Sidekiq
      def sidekiq_status
        stats = Sidekiq::Stats.new

        {
          enqueued: stats.enqueued,
          processed: stats.processed,
          failed: stats.failed,
          workers_size: stats.workers_size,
          queues: stats.queues
        }
      rescue => e
        { error: e.message }
      end

      # Перевірка з'єднання з базою даних
      def database_status
        { connected: ActiveRecord::Base.connection.active? }
      rescue => e
        { connected: false, error: e.message }
      end

      def port_open?(host, port)
        socket = TCPSocket.new(host, port)
        socket.close
        true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError
        false
      end
    end
  end
end
