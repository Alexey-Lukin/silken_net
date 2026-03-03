# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      # Користувач може бачити свій профіль, Адмін — усіх

      # --- СПИСОК ЕКІПАЖУ (The Crew) ---
      # GET /api/v1/users
      def index
        authorize_admin!
        scope = current_user.organization.users.order(last_seen_at: :desc, id: :desc)

        respond_to do |format|
          format.json do
            pagy, users = pagy(scope)
            render json: {
              data: UserBlueprint.render_as_hash(users, view: :crew),
              meta: pagy_metadata(pagy)
            }
          end
          format.html do
            @pagy, @users = pagy(scope)
            render_dashboard(
              title: "Crew Management // The Clan",
              component: Views::Components::Users::Index.new(users: @users)
            )
          end
        end
      end

      # --- ПРОФІЛЬ "Я" (Neural Link) ---
      # GET /api/v1/users/me
      def me
        @user = current_user

        respond_to do |format|
          format.json do
            render json: UserBlueprint.render(@user, view: :profile)
          end
          format.html do
            render_dashboard(
              title: "Profile // #{@user.first_name}",
              component: Views::Components::Users::Profile.new(user: @user)
            )
          end
        end
      end
    end
  end
end
