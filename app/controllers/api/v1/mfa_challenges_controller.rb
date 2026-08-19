# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # [S6.21] Другий фактор входу. Пароль пройдено → sessions#create кладе
    # pending-мітку і шле СЮДИ; сесія (`session[:user_id]`) НЕ існує, доки код
    # не підтверджено — «наполовину зайшов» не є станом.
    #
    # Pending живе PENDING_TTL: покинута форма не тримає半-вхід вічно, а
    # прострочення чесно вертає на логін (не 401 — людина нічого не порушила).
    class MfaChallengesController < BaseController
      skip_before_action :authenticate_user!

      PENDING_TTL = 5.minutes

      # Той самий брутфорс-бар, що на паролі (sessions#create: 5/хв) — інакше
      # другий фактор перебирається швидше за перший.
      rate_limit to: 5, within: 1.minute, only: :create, with: -> {
        respond_to do |format|
          format.json { render json: { error: I18n.t("flash.sessions.rate_limited") }, status: :too_many_requests }
          format.html do
            render_auth_page(
              title: I18n.t("sessions.mfa_challenge.title"),
              component: Sessions::MfaChallenge.new(flash_alert: I18n.t("flash.sessions.rate_limited")),
              status: :too_many_requests
            )
          end
        end
      }

      # --- ФОРМА ДРУГОГО ФАКТОРА ---
      # GET /login/mfa
      def new
        return redirect_to login_path unless pending_user

        render_auth_page(title: t("sessions.mfa_challenge.title"), component: Sessions::MfaChallenge.new)
      end

      # --- ПЕРЕВІРКА КОДУ / RECOVERY ---
      # POST /login/mfa
      def create
        user = pending_user
        return redirect_to login_path unless user

        if verify_second_factor(user)
          # Мітки згорають ДО establish_session: той робить reset_session сам
          # (анти-fixation), тож чистка тут — про те, щоб невдалий редирект після
          # встановлення не лишив живого pending.
          establish_session(user)

          I18n.with_locale(resolve_locale(account: user)) do
            respond_to do |format|
              format.json { render_api_login_success(user) }
              format.html { redirect_to dashboard_index_path, success: I18n.t("flash.sessions.neural_link_established") }
            end
          end
        else
          respond_to do |format|
            format.json { render json: { error: t("sessions.mfa_challenge.invalid_code") }, status: :unauthorized }
            format.html do
              render_auth_page(
                title: t("sessions.mfa_challenge.title"),
                component: Sessions::MfaChallenge.new(flash_alert: t("sessions.mfa_challenge.invalid_code")),
                status: :unauthorized
              )
            end
          end
        end
      end

      private

      # Pending-мітка валідна = id є І не прострочена. Прострочену чистимо одразу,
      # щоб форма не «оживала» від повторного сабміту.
      def pending_user
        id = session[:mfa_pending_user_id]
        at = session[:mfa_pending_at].to_i
        return nil if id.blank?

        if at < PENDING_TTL.ago.to_i
          clear_pending!
          return nil
        end

        User.find_by(id: id)
      end

      # TOTP першим (масовий шлях), recovery — запасний вихід із ВЛАСНИМ полем:
      # одне поле на обидва формати змусило б угадувати, який із них ввели, і
      # 8-hex recovery легко колізіює з «мало не 6 цифр» одруком.
      def verify_second_factor(user)
        code = params[:otp_code].to_s
        recovery = params[:recovery_code].to_s

        ok = if recovery.present?
          user.consume_recovery_code!(recovery)
        else
          user.verify_totp!(code)
        end
        clear_pending! if ok
        ok
      end

      def clear_pending!
        session.delete(:mfa_pending_user_id)
        session.delete(:mfa_pending_at)
      end
    end
  end
end
