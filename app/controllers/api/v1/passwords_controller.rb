# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class PasswordsController < BaseController
      # Дозволяємо доступ без автентифікації для скидання пароля
      skip_before_action :authenticate_user!, only: [ :new, :create, :edit, :update ]

      # Захист від перебору: обмеження кількості спроб запиту скидання
      rate_limit to: 3, within: 5.minutes, only: :create, with: -> {
        respond_to do |format|
          format.json { render json: { error: I18n.t("passwords.rate_limited") }, status: :too_many_requests }
          format.html { redirect_to forgot_password_path, alert: I18n.t("passwords.rate_limited") }
        end
      }

      # --- ФОРМА "ЗАБУВ ПАРОЛЬ" ---
      # GET /forgot_password
      def new
        respond_to do |format|
          format.html { render_auth_page(title: I18n.t("passwords.forgot_title"), component: Passwords::Forgot.new) }
        end
      end

      # --- ВІДПРАВКА EMAIL ДЛЯ СКИДАННЯ ---
      # POST /forgot_password
      def create
        user = User.find_by(email_address: params[:email])

        # Завжди показуємо однакову відповідь (захист від enumeration)
        if user.present?
          PasswordMailer.with(user: user).reset_instructions.deliver_later
        end

        respond_to do |format|
          format.json { render json: { message: I18n.t("passwords.forgot_sent_json") }, status: :ok }
          format.html { redirect_to login_path, notice: I18n.t("passwords.forgot_sent_flash") }
        end
      end

      # --- ФОРМА НОВОГО ПАРОЛЯ ---
      # GET /reset_password?token=xxx
      def edit
        respond_to do |format|
          format.html { render_auth_page(title: I18n.t("passwords.reset_title"), component: Passwords::Reset.new(token: params[:token])) }
        end
      end

      # --- ВСТАНОВЛЕННЯ НОВОГО ПАРОЛЯ ---
      # PATCH /reset_password
      def update
        user = User.find_by_token_for(:password_reset, params[:token])

        if user.nil?
          respond_to do |format|
            format.json { render json: { error: I18n.t("passwords.reset.invalid_token_json") }, status: :unprocessable_content }
            format.html { redirect_to forgot_password_path, alert: I18n.t("passwords.reset.invalid_token_flash") }
          end
          return
        end

        if params[:password].to_s.length < 12
          respond_to do |format|
            format.json { render json: { error: I18n.t("passwords.reset.too_short") }, status: :unprocessable_content }
            format.html do
              render_auth_page(
                title: I18n.t("passwords.reset_title"),
                component: Passwords::Reset.new(token: params[:token], flash_alert: I18n.t("passwords.reset.too_short")),
                # [SEC.25] Дзеркалить статус JSON-гілки. Тут ціна найвища в дереві:
                # без нього Turbo викидав відповідь, тобто людина, що скидає пароль,
                # вводила закороткий і не бачила ЖОДНОЇ реакції — при тому, що
                # компонент чесно приймав `flash_alert:` і чесно його рендерив.
                status: :unprocessable_content
              )
            end
          end
          return
        end

        if params[:password] != params[:password_confirmation]
          respond_to do |format|
            format.json { render json: { error: I18n.t("passwords.reset.mismatch") }, status: :unprocessable_content }
            format.html do
              render_auth_page(
                title: I18n.t("passwords.reset_title"),
                component: Passwords::Reset.new(token: params[:token], flash_alert: I18n.t("passwords.reset.mismatch")),
                status: :unprocessable_content
              )
            end
          end
          return
        end

        user.update!(password: params[:password])

        # [SEC.16] Reset = НАЙБІЛЬШ компрометаційно-підозрілий шлях — гасимо ВСІ
        # сесії (cookie й так стухнуть через salt-stamp; Session-журнал — явно).
        # Ініціатор не залогінений (public flow) — нема кого зберігати.
        user.sessions.destroy_all

        respond_to do |format|
          format.json { render json: { message: I18n.t("passwords.reset.updated_json") }, status: :ok }
          format.html { redirect_to login_path, notice: I18n.t("passwords.reset.updated_flash") }
        end
      end
    end
  end
end
