# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < BaseController
      # GET /api/v1/notifications/settings
      # Поточні налаштування каналів зв'язку для поточного користувача
      def settings
        respond_to do |format|
          format.json do
            render json: {
              user_id: current_user.id,
              channels: {
                email: current_user.email_address,
                phone: current_user.phone_number,
                telegram_chat_id: current_user.telegram_chat_id,
                push_token: current_user.push_token
              }
            }
          end
          format.html do
            render_dashboard(
              title: "Notification Channels",
              component: Notifications::Settings.new(user: current_user)
            )
          end
        end
      end

      # PATCH /api/v1/notifications/settings
      # Оновлення каналів зв'язку (Telegram, SMS, Push, Email)
      def update_settings
        if current_user.update(notification_params)
          respond_to do |format|
            format.json do
              render json: {
                message: "Налаштування сповіщень оновлено.",
                channels: {
                  email: current_user.email_address,
                  phone: current_user.phone_number,
                  telegram_chat_id: current_user.telegram_chat_id,
                  push_token: current_user.push_token
                }
              }
            end
            format.html { redirect_to api_v1_notifications_settings_path, notice: "Налаштування оновлено." }
          end
        else
          respond_to do |format|
            format.json { render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content }
            format.html do
              render_dashboard(
                title: "Notification Channels",
                component: Notifications::Settings.new(user: current_user)
              )
            end
          end
        end
      end

      private

      def notification_params
        params.permit(:phone_number, :telegram_chat_id, :push_token)
      end
    end
  end
end
