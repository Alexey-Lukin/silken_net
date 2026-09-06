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

      # [UI.16] Вікно пошуку останнього запису для плейсхолдера стрічки.
      # ⚠️ Це НЕ `partition_pruned`: той хелпер прунить звертання за ВІДОМИМ рядком
      # (секундне вікно навколо `created_at`), а тут множина невідомого розміру —
      # її прунить ІНДЕКС плюс явна межа (`CLAUDE.md §6`). Межа скінченна свідомо:
      # безмежний `ORDER BY created_at DESC LIMIT 1` сканував би всі партиції на
      # сторінці, яку відкривають щодня. Порожньо за вікном → чесне «очікуємо».
      IDLE_NOTICE_WINDOW = 7.days

      # --- ЖИВИЙ ПОТІК ІСТИНИ (The Pulse) ---
      # GET /telemetry/live
      def live
        respond_to do |format|
          format.html do
            render_dashboard(
              title: I18n.t("telemetry.live_title"),
              component: Telemetry::LiveStream.new(
                organization: acting_organization!,
                last_record: last_telemetry_record
              )
            )
          end
        end
      end

      # --- ДИХАННЯ СОЛДАТА (Існуючий метод) ---
      def tree_history
        @tree = acting_organization!.trees.find(params[:id])
        days = clamp_history_days(params[:days])
        logs = @tree.telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        # Оптимізація: використовуємо pluck замість map для зменшення навантаження на пам'ять
        plucked = logs.pluck(:created_at, :z_value, :temperature_c)

        # [ARCH.86] `z_value` віддається під власним іменем і БЕЗ одиниці: це
        # безрозмірна координата атрактора Лоренца, а не фізична величина.
        # Публікувати її зобов'язує відтворюваність — Z входить у Merkle-лист
        # (`TelemetryLog::LEAF_PAYLOAD_COLUMNS`), тож без нього зовнішній аудитор
        # не перерахує `archive_root` і не перевірить наш якір.
        # ⛔ Похідного «індексу стресу» тут немає СВІДОМО: Z — DCI/anti-fraud
        # сигнал, а не оракул здоров'я, і роль його вирішує ground-truth-протокол
        # (`05_05 §8`). Справжня метрика живе добовим зерном на AiInsight —
        # розмазати її по телеметричних мітках означало б виготовити роздільність,
        # якої модель не має.
        render json: {
          did: @tree.did,
          timestamps: plucked.map { |row| row[0].to_i },
          z_value: plucked.map { |row| row[1].to_f.round(2) },
          temperature: plucked.map { |row| row[2].to_f.round(2) }
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
        @gateway = acting_organization!.gateways.find(params[:id])

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

        # Аргументи UnpackTelemetryWorker: (encoded_payload, sender_ip, gateway_uid,
        # received_at_iso). Сигнатура ідентична виклику з CoAP-демона (`lib/coap_gate`).
        # [ARCH.41] Четвертий аргумент — момент прийому, зафіксований на межі: він
        # серіалізується в job і тому не рухається між Sidekiq-спробами, на відміну
        # від `Time.now` обробки та від `created_at` рядка.
        UnpackTelemetryWorker.perform_async(
          payload,
          request.remote_ip,
          @gateway.uid,
          Time.current.utc.iso8601
        )

        render json: {
          status: "accepted",
          gateway_uid: @gateway.uid
        }, status: :accepted
      end

      # --- ПУЛЬС КОРЛЕВИ (Існуючий метод) ---
      def gateway_history
        @gateway = acting_organization!.gateways.find(params[:id])
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

      # [UI.16] Найсвіжіший ПРИЙНЯТИЙ запис організації — вимір для плейсхолдера, а
      # не відтворення стрічки. Скоуп асоціативний (`acting_organization!`), тобто
      # чужий рядок не матеріалізується взагалі — та сама постава, що в решті
      # контролерів [SEC.25 Ф2].
      def last_telemetry_record
        TelemetryLog
          .where(tree_id: acting_organization!.trees.select(:id))
          .where(created_at: IDLE_NOTICE_WINDOW.ago..)
          .order(created_at: :desc)
          .first
      end

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
