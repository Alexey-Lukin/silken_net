# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      # Дозволяємо вхід без автентифікації (логічно, бо ми її тільки створюємо)
      skip_before_action :authenticate_user!, only: :create

      # --- ВХІД (Login) ---
      # POST /api/v1/login
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          # Генеруємо токен доступу (використовуємо Rails 8 generates_token_for)
          token = user.generate_token_for(:api_access)

          # Оновлюємо сесію для Web-дашборду
          session[:user_id] = user.id
          user.touch_visit!

          render json: {
            token: token,
            user: {
              id: user.id,
              email: user.email_address,
              full_name: user.full_name,
              role: user.role
            }
          }, status: :created
        else
          render json: { error: "Невірні координати доступу (Email або пароль)." }, status: :unauthorized
        end
      end

      # --- ВИХІД (Logout) ---
      # DELETE /api/v1/logout
      def destroy
        # Очищуємо сесію
        session[:user_id] = nil

        # В API-світі клієнт просто видаляє токен у себе,
        # але ми можемо додати логіку відкликання токена, якщо це необхідно.

        render json: { message: "Вихід успішний. Брама закрита." }, status: :ok
      end
    end
  end
end
