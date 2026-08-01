# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      before_action :authorize_admin!

      # GET /settings
      # Поточна конфігурація Організації
      def show
        org = acting_organization!

        respond_to do |format|
          format.json do
            render json: {
              organization: {
                id: org.id,
                name: org.name,
                billing_email: org.billing_email,
                crypto_public_address: org.crypto_public_address,
                alert_threshold_critical_z: org.alert_threshold_critical_z,
                ai_sensitivity: org.ai_sensitivity,
                logo_url: org.logo.attached? ? url_for(org.logo) : nil,
                created_at: org.created_at
              }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("settings.show_title"),
              component: Settings::Show.new(organization: org)
            )
          end
        end
      end

      # PATCH /settings
      # Оновлення конфігурації Організації (логотип, пороги тривоги, AI-чутливість)
      def update
        org = acting_organization!

        if org.update(settings_params)
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.settings.org_updated"),
                organization: {
                  id: org.id,
                  name: org.name,
                  billing_email: org.billing_email,
                  crypto_public_address: org.crypto_public_address,
                  alert_threshold_critical_z: org.alert_threshold_critical_z,
                  ai_sensitivity: org.ai_sensitivity,
                  logo_url: org.logo.attached? ? url_for(org.logo) : nil
                }
              }
            end
            # [SEC.25 Ф3] Дзеркало `notifications#update_settings`: HTML тепер каже
            # те саме, що JSON («Налаштування Організації»), а не загальніше.
            format.html { redirect_to settings_path, success: I18n.t("flash.settings.org_updated") }
          end
        else
          respond_to do |format|
            format.json { render json: { errors: org.errors.full_messages }, status: :unprocessable_content }
            # [SEC.25] Дзеркалить статус JSON-гілки рядком вище. Без нього Turbo
            # мовчки викидає відповідь (`200` без редиректу на сабміт), і форма з
            # помилкою виглядає для оператора як мертва кнопка.
            format.html do
              render_dashboard(
                title: I18n.t("settings.show_title"),
                component: Settings::Show.new(organization: org),
                status: :unprocessable_content
              )
            end
          end
        end
      end

      private

      # [I18N.1] `:locale` — мова, якою організація отримує ПОШТУ (`AlertMailer`
      # шле на `billing_email`, за яким може не стояти жоден User, тож локаль
      # користувача тут не підходить). Валідацію значення тримає модель.
      def settings_params
        params.require(:organization).permit(:name, :billing_email, :crypto_public_address,
                                             :alert_threshold_critical_z, :ai_sensitivity, :logo,
                                             :locale)
      end
    end
  end
end
