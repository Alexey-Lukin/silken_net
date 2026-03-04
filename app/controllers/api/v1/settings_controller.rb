# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      before_action :authorize_admin!

      # GET /api/v1/settings
      # Поточна конфігурація Організації
      def show
        org = current_user.organization

        render json: {
          organization: {
            id: org.id,
            name: org.name,
            billing_email: org.billing_email,
            crypto_public_address: org.crypto_public_address,
            created_at: org.created_at
          }
        }
      end

      # PATCH /api/v1/settings
      # Оновлення конфігурації Організації (логотип, пороги тривоги, тощо)
      def update
        org = current_user.organization

        if org.update(settings_params)
          render json: {
            message: "Налаштування Організації оновлено.",
            organization: {
              id: org.id,
              name: org.name,
              billing_email: org.billing_email,
              crypto_public_address: org.crypto_public_address
            }
          }
        else
          render json: { errors: org.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def settings_params
        params.require(:organization).permit(:name, :billing_email, :crypto_public_address)
      end
    end
  end
end
