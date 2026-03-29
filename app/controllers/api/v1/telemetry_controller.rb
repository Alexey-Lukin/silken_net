# frozen_string_literal: true

module Api
  module V1
    class TelemetryController < BaseController
      # --- ЖИВИЙ ПОТІК ІСТИНИ (The Pulse) ---
      # GET /api/v1/telemetry/live
      def live
        respond_to do |format|
          format.html do
            render_dashboard(
              title: "Live Telemetry // The Pulse",
              component: Telemetry::LiveStream.new
            )
          end
        end
      end

      # --- ДИХАННЯ СОЛДАТА (Існуючий метод) ---
      def tree_history
        @tree = current_user.organization.trees.find(params[:id])
        days = (params[:days] || 7).to_i
        logs = @tree.telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        # Оптимізація: використовуємо pluck замість map для зменшення навантаження на пам'ять
        plucked = logs.pluck(:created_at, :z_value, :temperature_c)
        baseline = @tree.tree_family.baseline_impedance

        render json: {
          did: @tree.did,
          unit: "kOhm",
          timestamps: plucked.map { |row| row[0].to_i },
          impedance: plucked.map { |row| row[1].to_f.round(2) },
          temperature: plucked.map { |row| row[2].to_f.round(2) },
          stress_index: plucked.map { |row| (1.0 - (row[1].to_f / baseline)).round(3) }
        }
      end

      # --- HTTP TELEMETRY UPLINK (POST /api/v1/gateways/:id/telemetry) ---
      # Основний канал передачі телеметрії від Gateway — CoAP/UDP на порт 5683
      # через Starlink Direct-to-Cell / LTE (SIM7070G AT+CCOAPSEND).
      # Цей HTTP ендпоінт доступний для:
      #   1. Сценаріїв, де CoAP/UDP заблоковано (корпоративні фаєрволи, LTE UDP обмеження)
      #   2. Phase 3 Starlink Mini з TCP/IP мостом (ESP32/SIM8200G-M2)
      #   3. Ручного завантаження телеметрії через Dashboard (forester upload)
      # Приймає Base64-кодований бінарний батч зашифрованих пакетів від Gateway.
      # Формат ідентичний CoAP uplink: [IV:16][AES-256-CBC encrypted 21-byte records]
      def gateway_uplink
        @gateway = current_user.organization.gateways.find(params[:id])

        payload = params.require(:payload)

        # Аргументи UnpackTelemetryWorker: (encoded_payload, sender_ip, gateway_uid)
        # Сигнатура ідентична виклику з CoAP daemon (lib/daemons/coap_listener).
        UnpackTelemetryWorker.perform_async(
          payload,
          request.remote_ip,
          @gateway.uid
        )

        @gateway.mark_seen!(new_ip: request.remote_ip)

        render json: {
          status: "accepted",
          gateway_uid: @gateway.uid
        }, status: :accepted
      end

      # --- ПУЛЬС КОРЛЕВИ (Існуючий метод) ---
      def gateway_history
        @gateway = current_user.organization.gateways.find(params[:id])
        days = (params[:days] || 7).to_i
        logs = @gateway.gateway_telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        # Оптимізація: використовуємо pluck замість map
        plucked = logs.pluck(:created_at, :voltage_mv, :cellular_signal_csq, :temperature_c)

        render json: {
          uid: @gateway.uid,
          timestamps: plucked.map { |row| row[0].to_i },
          voltage: plucked.map { |row| row[1] },
          signal: plucked.map { |row| row[2] },
          temp: plucked.map { |row| row[3] }
        }
      end
    end
  end
end
