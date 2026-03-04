# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < BaseController
      # GET /api/v1/notifications/settings
      # Поточні налаштування каналів зв'язку для поточного користувача
      def settings
        render json: {
          user_id: current_user.id,
          channels: {
            email: current_user.email_address,
            phone: current_user.phone_number,
            telegram_chat_id: current_user.telegram_chat_id
          }
        }
      end

      # PATCH /api/v1/notifications/settings
      # Оновлення каналів зв'язку (Telegram, SMS, Push, Email)
      def update_settings
        if current_user.update(notification_params)
          render json: {
            message: "Налаштування сповіщень оновлено.",
            channels: {
              email: current_user.email_address,
              phone: current_user.phone_number,
              telegram_chat_id: current_user.telegram_chat_id
            }
          }
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def notification_params
        params.permit(:phone_number, :telegram_chat_id)
      end
    end
  end
end
