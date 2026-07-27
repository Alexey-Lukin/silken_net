# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class TelemetryController < BaseController
      # 16 KB is a generous ceiling for a single Gateway batch: 21-byte
      # encrypted records × ~700 entries × Base64 overhead (4/3) ≈ 19,600 bytes.
      # Real-world batches flush at 45 entries, so 16 KB is ~16× headroom.
      # Without this an attacker holding a Bearer token could POST megabyte
      # payloads that occupy Puma worker threads and reach Sidekiq queues.
      MAX_UPLINK_PAYLOAD_SIZE = 16.kilobytes

      # Cap on `?days=` for history endpoints. Beyond a year the response is
      # millions of rows of telemetry, which exhausts Ruby memory and is
      # never a legitimate user request — chronicle/charting tools page
      # through history in smaller windows.
      MAX_HISTORY_DAYS = 365
      DEFAULT_HISTORY_DAYS = 7

      # --- ЖИВИЙ ПОТІК ІСТИНИ (The Pulse) ---
      # GET /api/v1/telemetry/live
      def live
        respond_to do |format|
          format.html do
            render_dashboard(
              title: I18n.t("telemetry.live_title"),
              component: Telemetry::LiveStream.new(organization: current_user.organization)
            )
          end
        end
      end

      # --- ДИХАННЯ СОЛДАТА (Існуючий метод) ---
      def tree_history
        @tree = current_user.organization.trees.find(params[:id])
        days = clamp_history_days(params[:days])
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
      #
      # [A-8 FIX]: Controller is fully stateless — zero DB writes in the HTTP hot-path.
      # mark_seen! is handled inside UnpackTelemetryWorker (line 42) to avoid
      # Connection Pool Exhaustion during mass gateway reconnects after blackouts.
      def gateway_uplink
        @gateway = current_user.organization.gateways.find(params[:id])

        payload = params.require(:payload).to_s

        # [DoS GUARD]: cap the payload before it leaves the request thread.
        # Sidekiq enqueues `payload` straight into Redis — letting a megabyte
        # blob through wastes both Puma memory and Redis. The CoAP daemon
        # already enforces a strict size limit upstream.
        if payload.bytesize > MAX_UPLINK_PAYLOAD_SIZE
          # Rack 3 renamed :payload_too_large → :content_too_large (both 413).
          # Use the new symbol to dodge the deprecation warning emitted by
          # ActionDispatch::Response and rspec-rails matchers.
          render json: {
            error: I18n.t("flash.telemetry.payload_too_large", limit: MAX_UPLINK_PAYLOAD_SIZE / 1.kilobyte)
          }, status: :content_too_large
          return
        end

        # Аргументи UnpackTelemetryWorker: (encoded_payload, sender_ip, gateway_uid)
        # Сигнатура ідентична виклику з CoAP daemon (lib/daemons/coap_listener).
        UnpackTelemetryWorker.perform_async(
          payload,
          request.remote_ip,
          @gateway.uid
        )

        render json: {
          status: "accepted",
          gateway_uid: @gateway.uid
        }, status: :accepted
      end

      # --- ПУЛЬС КОРЛЕВИ (Існуючий метод) ---
      def gateway_history
        @gateway = current_user.organization.gateways.find(params[:id])
        days = clamp_history_days(params[:days])
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

      private

      # `to_i` swallows non-numeric input as 0 (silently returning an empty
      # window). Clamp into [1, MAX_HISTORY_DAYS] so that bogus or unbounded
      # input gracefully degrades to the default rather than nothing.
      def clamp_history_days(raw)
        n = raw.to_i
        n = DEFAULT_HISTORY_DAYS if n <= 0
        [ n, MAX_HISTORY_DAYS ].min
      end
    end
  end
end
