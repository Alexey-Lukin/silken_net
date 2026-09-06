# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < BaseController
      # GET /notifications/settings
      # Поточні налаштування каналів зв'язку для поточного користувача
      def settings
        respond_to do |format|
          format.json do
            render json: {
              user_id: current_user.id,
              channels: {
                email: current_user.email_address,
                push_token: current_user.push_token
              }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("notifications.settings_title"),
              component: Notifications::Settings.new(
                user: current_user,
                available_channels: Notifications::DeliveryChannels.available
              )
            )
          end
        end
      end

      # PATCH /notifications/settings
      # Оновлення каналів зв'язку (Push, Email) — ⚫ Telegram знято [ARCH.60] 2026-09-06.
      def update_settings
        if current_user.update(notification_params)
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.notifications.updated"),
                channels: {
                  email: current_user.email_address,
                  push_token: current_user.push_token
                }
              }
            end
            # [SEC.25 Ф3] Той самий ключ, що й у JSON-гілці вище. Доти HTML брав
            # загальний ключ сусіднього settings-домену, тобто браузерний
            # користувач — єдиний, хто повідомлення взагалі БАЧИТЬ, — діставав
            # текст РОЗМИТІШИЙ за той, що йшов API-клієнтові.
            format.html { redirect_to notifications_settings_path, success: I18n.t("flash.notifications.updated") }
          end
        else
          respond_to do |format|
            format.json { render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content }
            # [SEC.25] Дзеркалить статус JSON-гілки — на `200` без редиректу Turbo
            # відповідь викидає, і сабміт виглядає як no-op.
            format.html do
              render_dashboard(
                title: I18n.t("notifications.settings_title"),
                component: Notifications::Settings.new(
                user: current_user,
                available_channels: Notifications::DeliveryChannels.available
              ),
                status: :unprocessable_content
              )
            end
          end
        end
      end

      private

      def notification_params
        params.permit(:push_token)
      end
    end
  end
end
