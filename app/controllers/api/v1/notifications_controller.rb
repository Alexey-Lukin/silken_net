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

      # ⛔ PATCH /notifications/settings — ВИДАЛЕНО 2026-09-06 [ARCH.60, ⚖️ founder].
      #
      # Екшен приймав РІВНО ОДНЕ поле — `push_token`, — а транспорту для нього не
      # існує: `DeliveryChannels.available?(:push)` віддає жорсткий `false`, FCM-
      # адаптера в дереві нуль. Збирати ідентифікатор пристрою під канал, якого
      # немає, не проходить Art.5(1)(c) GDPR: Recital 39 вимагає, щоб цілі були
      # «determined at the time of the collection», а WP29 (WP203) прямо каже, що
      # загальне «future use» критерію «specific» не проходить. Той самий критерій
      # уже зрізав `phone_number` (ARCH.78) і `telegram_chat_id` (ARCH.60) — цей
      # третій.
      #
      # 🔴 Чому знято ЕКШЕН, а не лише поле з `permit`: `notification_params` ніс
      # один ключ, тож зняття лишило б `permit()` порожнім, а `update({})` повертає
      # **true** — користувач бачив би «збережено» там, де не збережено нічого
      # (інваріант CLAUDE.md §6). Тихий успіх гірший за відсутню дію.
      #
      # ⊕ Колонка `users.push_token` ЛИШАЄТЬСЯ свідомо: канал не відкинуто, а
      # ⚖️-відкладено до появи мобільного клієнта (ARCH.108), тож майбутня нога
      # нічого не втрачає — припиняється саме ЗБІР. Читання стану лишається в
      # `#settings`; `Gdpr::DataExportService` і `AnonymizeUserService` колонку
      # далі бачать, бо історичні значення нікуди не діваються.
    end
  end
end
