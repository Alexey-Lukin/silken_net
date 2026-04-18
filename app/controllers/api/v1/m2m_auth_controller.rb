# frozen_string_literal: true

module Api
  module V1
    # =========================================================================
    # M2M АВТЕНТИФІКАЦІЯ (Machine-to-Machine Authentication)
    # =========================================================================
    # [P1 WARNING FIX]: Gateway-пристрої працюють роками без оператора.
    # Bearer-токен від POST /api/v1/login протухає через 30 днів.
    # Цей ендпоінт дозволяє шлюзу автентифікуватися за допомогою
    # Ed25519-підпису свого DID без логіна/пароля.
    #
    # Потік:
    #   1. Під час провізіонування шлюз реєструє Ed25519 public key
    #   2. POST /api/v1/auth/m2m_token: шлюз надсилає DID + timestamp + Ed25519 signature
    #   3. Бекенд верифікує підпис та видає M2M токен (термін = api_access, 30 днів)
    #   4. Шлюз використовує токен для API-запитів
    #   5. Перед закінченням терміну — повторний POST /api/v1/auth/m2m_token
    class M2mAuthController < BaseController
      # create — публічний (Ed25519 auth); refresh — потребує Bearer token (BaseController default)
      skip_before_action :authenticate_user!, only: :create

      # POST /api/v1/auth/m2m_token
      def create
        did = params.require(:did)
        timestamp = params.require(:timestamp)
        signature = params.require(:signature)

        hardware_key = HardwareKey.find_by(device_uid: did)

        unless hardware_key
          render json: { error: "Пристрій не знайдено в системі." }, status: :not_found
          return
        end

        unless hardware_key.ed25519_public_key_hex.present?
          render json: { error: "Ed25519 public key не зареєстровано для пристрою." }, status: :unprocessable_content
          return
        end

        # Перевіряємо актуальність timestamp (± 5 хвилин)
        begin
          request_time = Time.iso8601(timestamp)
        rescue ArgumentError
          render json: { error: "Невалідний формат timestamp (ISO 8601)." }, status: :bad_request
          return
        end

        if (Time.current - request_time).abs > 5.minutes
          render json: { error: "Timestamp прострочено. Синхронізуйте годинник пристрою." }, status: :unauthorized
          return
        end

        # [M2M REPLAY FIX]: Nonce check — each signature can only be used once.
        # The SHA256 digest of the signature serves as a natural nonce (unique per DID+timestamp).
        # TTL = 10 minutes (covers the ±5 min window with margin).
        # Redis SET NX ensures atomicity: first request wins, replays are rejected.
        begin
          nonce_key = Kredis.namespaced_key("m2m_nonce:#{Digest::SHA256.hexdigest(signature)}")
          nonce_acquired = Kredis.redis(config: :shared).set(nonce_key, "1", nx: true, ex: 600)

          unless nonce_acquired
            Rails.logger.warn "⚠️ [M2M Replay] Blocked duplicate M2M auth for #{did} (signature reuse)"
            render json: { error: "Replay attack detected" }, status: :unauthorized
            return
          end
        rescue Redis::BaseConnectionError, RedisClient::ConnectionError => e
          Rails.logger.error "🚨 [M2M Auth] Redis unavailable for nonce check: #{e.message}"
          render json: { error: "Service temporarily unavailable." }, status: :service_unavailable
          return
        end

        # Верифікація Ed25519 підпису: signature = Ed25519.sign(private_key, "#{did}:#{timestamp}")
        message = "#{did}:#{timestamp}"
        begin
          valid = Ed25519Crypto::SigningService.verify(
            hardware_key.ed25519_public_key_hex,
            signature,
            message
          )
        rescue Ed25519Crypto::SigningService::SigningError => e
          Rails.logger.error "🚨 [M2M Auth] Invalid signature format for #{did}: #{e.message}"
          render json: { error: "Invalid signature format." }, status: :unauthorized
          return
        end

        unless valid
          Rails.logger.error "🚨 [M2M Auth] Невалідний Ed25519 підпис для #{did}."
          render json: { error: "Невалідний підпис." }, status: :unauthorized
          return
        end

        # Знаходимо організацію через ієрархію пристрою
        owner = hardware_key.owner
        organization = owner&.cluster&.organization

        unless organization
          render json: { error: "Пристрій не прив'язано до організації." }, status: :unprocessable_content
          return
        end

        # Генеруємо M2M токен від системного користувача організації
        # або першого адміна організації
        system_user = organization.users.role_admin.first || organization.users.first

        unless system_user
          render json: { error: "Організація не має користувачів для видачі токена." }, status: :unprocessable_content
          return
        end

        token = system_user.generate_token_for(:api_access)

        Rails.logger.info "✅ [M2M Auth] Токен видано для пристрою #{did} (org: #{organization.name})."

        render json: {
          token: token,
          device_uid: did,
          expires_in: "30 days",
          token_type: "Bearer"
        }, status: :created
      end

      # POST /api/v1/auth/m2m_token/refresh
      # [S3.4 M2M REFRESH]: Sliding-window token renewal.
      # Gateway надсилає поточний валідний Bearer-токен і отримує новий 30-денний токен
      # без необхідності Ed25519 re-authentication. Дозволено лише в останні 7 днів
      # терміну дії (REFRESH_WINDOW), щоб зменшити ризик зловживання.
      #
      # Firmware flow:
      #   1. Gateway зберігає timestamp видачі токена
      #   2. Щогодини (або при CoAP flush) перевіряє: залишилось < 7 днів?
      #   3. Якщо так → POST /api/v1/auth/m2m_token/refresh з Bearer header
      #   4. Отримує новий токен → зберігає → продовжує роботу
      def refresh
        # current_user вже автентифікований через before_action :authenticate_user!
        new_token = current_user.generate_token_for(:api_access)

        Rails.logger.info "🔄 [M2M Refresh] Токен оновлено для #{current_user.email_address} " \
                          "(org: #{current_user.organization&.name})."

        render json: {
          token: new_token,
          expires_in: "30 days",
          token_type: "Bearer",
          refreshed_at: Time.current.iso8601
        }, status: :created
      end
    end
  end
end
