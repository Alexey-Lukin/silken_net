# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # =========================================================================
    # M2M АВТЕНТИФІКАЦІЯ (Machine-to-Machine Authentication)
    # =========================================================================
    # [P1 WARNING FIX]: Gateway-пристрої працюють роками без оператора.
    # Bearer-токен від POST /login протухає через 30 днів.
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

      # 🔴 [SEC.30] Найдорожчий член класу: без цього рядка ШЛЮЗИ НЕ МОГЛИ ОТРИМАТИ
      # ТОКЕН узагалі — `verify_authenticity_token` лишався в ланцюгу, а Ed25519-підпис
      # їде в тілі, не в `Authorization: Bearer`, тож `handle_unverified_request` його
      # не впізнавав і валив запит у 500 до будь-якої криптоперевірки.
      # ⚠️ `only: :create` — НЕ косметика: `refresh` автентифікується `authenticate_user!`,
      # який приймає І cookie-сесію, а там ambient authority реальна й CSRF несучий.
      # Знімати захист на весь контролер означало б полагодити машинний вхід ціною
      # відкриття браузерного.
      skip_forgery_protection only: :create

      # POST /api/v1/auth/m2m_token
      def create
        did = params.require(:did)
        timestamp = params.require(:timestamp)
        signature = params.require(:signature)

        hardware_key = HardwareKey.find_by(device_uid: did)

        unless hardware_key
          render json: { error: I18n.t("m2m_auth.device_not_found") }, status: :not_found
          return
        end

        unless hardware_key.ed25519_public_key_hex.present?
          render json: { error: I18n.t("m2m_auth.no_public_key") }, status: :unprocessable_content
          return
        end

        # Перевіряємо актуальність timestamp (± 5 хвилин)
        #
        # `Time.zone.iso8601`, ніколи голий `Time.iso8601` [ARCH.92]: другий читає
        # зону ПРОЦЕСУ, тож підпис із рядком без суфікса зони зсувався б на
        # UTC-офсет хоста — а тут це fail-closed-вікно, тобто чесний шлюз діставав
        # би 401 через середовище, а не через свій підпис.
        #
        # ⚠️ Явна вимога часу несуча: `Time.zone.iso8601` приймає дату-без-часу
        # (`2026-05-23` → північ), і без цього гарда вона мовчки пройшла б парс,
        # щоб упасти вже на вікні — тобто «невалідний timestamp» (400) вироджувався
        # б у «прострочений» (401), і клієнт шукав би розсинхрон годинника.
        begin
          raise ArgumentError, "timestamp without a time component" unless timestamp.to_s.include?("T")

          request_time = Time.zone.iso8601(timestamp)
        rescue ArgumentError
          render json: { error: I18n.t("m2m_auth.invalid_timestamp") }, status: :bad_request
          return
        end

        if (Time.current - request_time).abs > 5.minutes
          render json: { error: I18n.t("m2m_auth.timestamp_expired") }, status: :unauthorized
          return
        end

        # [M2M REPLAY FIX]: Nonce check — each signature can only be used once.
        # The SHA256 digest of the signature serves as a natural nonce (unique per DID+timestamp).
        # [S6.18 TTL JUSTIFICATION]: TTL = 10 minutes (600s).
        #   - Timestamp validity window: ±5 min (covers clock drift between gateway RTC and server).
        #   - Maximum signature lifetime: 10 min (gateway-side staleness + server-side delay margin).
        #   - Why not 5 min: a signature created at the trailing edge of the timestamp window
        #     (i.e., 5 minutes ago, still within timestamp tolerance) and replayed immediately
        #     would slip through if TTL == window. 10 min = window + margin guarantees nonce
        #     coverage for the entire period a signature could be considered valid.
        #   - Why not 15+ min: longer TTL increases Redis memory footprint per gateway (negligible
        #     individually, but at 100k+ devices and burst auth flows it adds up) without
        #     additional security benefit since timestamps older than 5 min are already rejected.
        # Redis SET NX ensures atomicity: first request wins, replays are rejected.
        nonce_digest = Digest::SHA256.hexdigest(signature)

        begin
          nonce_key = Kredis.namespaced_key("m2m_nonce:#{nonce_digest}")
          nonce_acquired = Kredis.redis(config: :shared).set(nonce_key, "1", nx: true, ex: 600)

          unless nonce_acquired
            Rails.logger.warn "⚠️ [M2M Replay] Blocked duplicate M2M auth for #{did} (signature reuse)"
            render json: { error: I18n.t("m2m_auth.replay_detected") }, status: :unauthorized
            return
          end
        rescue Redis::BaseConnectionError, RedisClient::ConnectionError => e
          # [S6.1]: Graceful degradation — fallback to Solid Cache (DB-backed)
          # when Redis is unavailable. Gateways remain operational instead of 503.
          # [ARCH.105] Фолбек АТОМАРНИЙ так само, як первинний шлях: `write` із
          # `unless_exist: true` — це SET NX самого сховища, а не пара
          # exist?/write. Доти тут стояло read-then-write із нотою «прийнятний
          # компроміс», і саме її спростували двоє сусідів по дереву, які вже
          # вживали атомарну форму на ТОМУ САМОМУ Solid Cache: компроміс був не
          # платою за деградацію, а невикористаним примітивом.
          # [S6.19]: Counter живить Grafana-алерт sn-alert-m2m-nonce-fallback
          # (escalation-семантика multi-zone Upstash — дім: 04_03 §5.15).
          SilkenNet::Metrics::M2M_NONCE_FALLBACK_TOTAL.increment
          Rails.logger.warn "⚠️ [M2M Auth] Redis unavailable, falling back to DB-based nonce check: #{e.message}"

          fallback_key = "m2m_nonce_fallback:#{nonce_digest}"

          unless Rails.cache.write(fallback_key, true, expires_in: 10.minutes, unless_exist: true)
            Rails.logger.warn "⚠️ [M2M Replay] Blocked duplicate M2M auth for #{did} (DB fallback, signature reuse)"
            render json: { error: I18n.t("m2m_auth.replay_detected") }, status: :unauthorized
            return
          end
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
          render json: { error: I18n.t("m2m_auth.invalid_signature_format") }, status: :unauthorized
          return
        end

        unless valid
          Rails.logger.error "🚨 [M2M Auth] Невалідний Ed25519 підпис для #{did}."
          render json: { error: I18n.t("m2m_auth.invalid_signature") }, status: :unauthorized
          return
        end

        # Знаходимо організацію через ієрархію пристрою
        owner = hardware_key.owner
        organization = owner&.cluster&.organization

        unless organization
          render json: { error: I18n.t("m2m_auth.device_no_organization") }, status: :unprocessable_content
          return
        end

        # Генеруємо M2M токен від системного користувача організації
        # або першого адміна організації
        system_user = organization.users.role_admin.first || organization.users.first

        unless system_user
          render json: { error: I18n.t("m2m_auth.no_users_in_organization") }, status: :unprocessable_content
          return
        end

        # [SEC.16] `:m2m_access`, а НЕ `:api_access`: доти шлюз діставав токен,
        # нерозрізнимий від людського admin-Bearer'а, і компрометована Королева
        # відкривала повний admin-API організації. Purpose ізолює криптографічно,
        # а `BaseController::M2M_ALLOWED_ACTIONS` тримає стелю поверхні.
        token = system_user.generate_token_for(:m2m_access)

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
        #
        # 🔴 [SEC.16] Purpose видається ТОЙ САМИЙ, яким прийшли, і це замикає
        # обхід, який інакше коштував би одного запиту: машина з `:m2m_access`
        # приходить сюди (екшен у її allowlist'і), а виходила б із `:api_access`,
        # тобто **сама себе підвищувала б до повного admin-scope**. Звуження при
        # видачі без цього рядка є декорацією з життям в один refresh-цикл.
        new_token = current_user.generate_token_for(machine_token? ? :m2m_access : :api_access)

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
