# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # [ARCH.34 L3] Helium SOS — «крик» Королеви через чужі hotspot'и, коли
    # впали ВСІ власні uplink'и (Starlink/LTE + Q2Q). Дзеркальний до
    # queen_offline (там Rails детектить ТИШУ, тут Королева ще жива і
    # КРИЧИТЬ). Транспорт: LoRaWAN → Helium LNS → HTTP Integration webhook
    # сюди. Канон: 06_08 §1.2 L3 (wire 12B) + 02_05 §6.1.
    #
    # Auth = клон перевіреного патерну oracle_callbacks: публічний POST +
    # HMAC-SHA256 над сирим тілом у заголовку + strict-mode fail-fast +
    # Rack::Attack throttle. Тонкий контролер: розбір/алерт — у воркері
    # (черга alerts — SOS і Є алерт).
    class HeliumSosController < BaseController
      # Helium Console webhook — machine-to-machine, без сесії користувача.
      skip_before_action :authenticate_user!

      before_action :verify_helium_signature!

      # POST /api/v1/telemetry/helium
      # Тіло (Helium Console HTTP Integration JSON): dev_eui (hex),
      # payload (base64 від 12B SOS-кадру), reported_at (ms epoch) — решту
      # полів Console'а ігноруємо (YAGNI до живої інтеграції).
      def create
        dev_eui = params[:dev_eui].presence || params[:devEUI].presence
        payload = params[:payload].presence

        if dev_eui.blank? || payload.blank?
          return render json: { error: "dev_eui and payload are required" },
                        status: :unprocessable_content
        end

        HeliumSosWorker.perform_async(dev_eui.to_s, payload.to_s,
                                      params[:reported_at].presence)
        head :accepted
      end

      private

      # HMAC-SHA256(raw_body, HELIUM_WEBHOOK_SECRET) у X-Helium-Signature —
      # Console шле кастомний заголовок зі спільним секретом. Той самий
      # життєвий цикл, що verify_chainlink_signature! (SEC.5-патерн):
      # секрет відсутній → dev/test пропуск з попередженням, у
      # WEB3_STRICT_MODE — SecurityError (endpoint без HMAC не живе в prod).
      def verify_helium_signature!
        hmac_secret = ENV["HELIUM_WEBHOOK_SECRET"]

        if hmac_secret.blank?
          # [SEC.5]: fail-closed і в prod (не лише під прапором) — mint/SOS
          # endpoint без HMAC не сміє жити, якщо WEB3_STRICT_MODE забули виставити.
          if ENV["WEB3_STRICT_MODE"] == "true" || Rails.env.production?
            raise SecurityError,
                  "HELIUM_WEBHOOK_SECRET обов'язковий у production / WEB3_STRICT_MODE. " \
                  "Helium SOS endpoint незахищений без HMAC верифікації."
          end

          Rails.logger.warn "⚠️ [Helium Security] HELIUM_WEBHOOK_SECRET не встановлено " \
                            "(dev/test — bypass із попередженням)."
          return
        end

        signature = request.headers["X-Helium-Signature"]

        if signature.blank?
          render json: { error: "Missing X-Helium-Signature header" }, status: :unauthorized
          return
        end

        expected = OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, request.raw_post)

        unless ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
          Rails.logger.error "🚨 [Helium Security] Невалідний HMAC-підпис SOS-webhook'а."
          render json: { error: "Invalid signature" }, status: :unauthorized
        end
      end
    end
  end
end
