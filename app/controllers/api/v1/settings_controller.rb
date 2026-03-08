# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      before_action :authorize_admin!

      # GET /api/v1/settings
      # Поточна конфігурація Організації
      def show
        org = current_user.organization

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
              title: "Organization Settings",
              component: Settings::Show.new(organization: org)
            )
          end
        end
      end

      # PATCH /api/v1/settings
      # Оновлення конфігурації Організації (логотип, пороги тривоги, AI-чутливість)
      def update
        org = current_user.organization

        if org.update(settings_params)
          respond_to do |format|
            format.json do
              render json: {
                message: "Налаштування Організації оновлено.",
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
            format.html { redirect_to api_v1_settings_path, notice: "Налаштування оновлено." }
          end
        else
          respond_to do |format|
            format.json { render json: { errors: org.errors.full_messages }, status: :unprocessable_entity }
            format.html do
              render_dashboard(
                title: "Organization Settings",
                component: Settings::Show.new(organization: org)
              )
            end
          end
        end
      end

      private

      def settings_params
        params.require(:organization).permit(:name, :billing_email, :crypto_public_address,
                                             :alert_threshold_critical_z, :ai_sensitivity, :logo)
      end
    end
  end
end
