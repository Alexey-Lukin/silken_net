# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      # Користувач може бачити свій профіль, Адмін — усіх
      
      # --- ПРОФІЛЬ "Я" ---
      # GET /api/v1/users/me
      def me
        render json: current_user.as_json(
          only: [:id, :email_address, :first_name, :last_name, :role, :last_seen_at]
        )
      end

      # --- СПИСОК ПАТРУЛЬНИХ ---
      # GET /api/v1/users
      def index
        authorize_admin!
        @users = current_user.organization.users.order(last_seen_at: :desc)
        
        render json: @users.as_json(
          only: [:id, :first_name, :last_name, :role, :last_seen_at],
          methods: [:full_name]
        )
      end
    end
  end
end
