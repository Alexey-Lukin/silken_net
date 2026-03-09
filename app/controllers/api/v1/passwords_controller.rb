# frozen_string_literal: true

module Api
  module V1
    class PasswordsController < BaseController
      # Дозволяємо доступ без автентифікації для скидання пароля
      skip_before_action :authenticate_user!, only: [ :new, :create, :edit, :update ]

      # Захист від перебору: обмеження кількості спроб запиту скидання
      rate_limit to: 3, within: 5.minutes, only: :create, with: -> {
        respond_to do |format|
          format.json { render json: { error: "Забагато спроб. Спробуйте через 5 хвилин." }, status: :too_many_requests }
          format.html { redirect_to api_v1_forgot_password_path, alert: "Забагато спроб. Спробуйте через 5 хвилин." }
        end
      }

      # --- ФОРМА "ЗАБУВ ПАРОЛЬ" ---
      # GET /api/v1/forgot_password
      def new
        respond_to do |format|
          format.html { render Passwords::Forgot.new }
        end
      end

      # --- ВІДПРАВКА EMAIL ДЛЯ СКИДАННЯ ---
      # POST /api/v1/forgot_password
      def create
        user = User.find_by(email_address: params[:email])

        # Завжди показуємо однакову відповідь (захист від enumeration)
        if user.present?
          PasswordMailer.with(user: user).reset_instructions.deliver_later
        end

        respond_to do |format|
          format.json { render json: { message: "Якщо email існує в системі, ви отримаєте інструкції для скидання пароля." }, status: :ok }
          format.html { redirect_to api_v1_login_path, notice: "Якщо email існує, ви отримаєте лист з інструкціями." }
        end
      end

      # --- ФОРМА НОВОГО ПАРОЛЯ ---
      # GET /api/v1/reset_password?token=xxx
      def edit
        respond_to do |format|
          format.html { render Passwords::Reset.new(token: params[:token]) }
        end
      end

      # --- ВСТАНОВЛЕННЯ НОВОГО ПАРОЛЯ ---
      # PATCH /api/v1/reset_password
      def update
        user = User.find_by_token_for(:password_reset, params[:token])

        if user.nil?
          respond_to do |format|
            format.json { render json: { error: "Токен скидання невалідний або протермінований." }, status: :unprocessable_content }
            format.html { redirect_to api_v1_forgot_password_path, alert: "Токен протермінований. Запросіть скидання повторно." }
          end
          return
        end

        if params[:password].to_s.length < 12
          respond_to do |format|
            format.json { render json: { error: "Пароль повинен містити мінімум 12 символів." }, status: :unprocessable_content }
            format.html do
              flash.now[:alert] = "Пароль повинен містити мінімум 12 символів."
              render Passwords::Reset.new(token: params[:token])
            end
          end
          return
        end

        if params[:password] != params[:password_confirmation]
          respond_to do |format|
            format.json { render json: { error: "Паролі не співпадають." }, status: :unprocessable_content }
            format.html do
              flash.now[:alert] = "Паролі не співпадають."
              render Passwords::Reset.new(token: params[:token])
            end
          end
          return
        end

        user.update!(password: params[:password])

        respond_to do |format|
          format.json { render json: { message: "Пароль успішно оновлено." }, status: :ok }
          format.html { redirect_to api_v1_login_path, notice: "Пароль оновлено. Увійдіть з новим паролем." }
        end
      end
    end
  end
end
