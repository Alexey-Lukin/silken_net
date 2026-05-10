# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      # --- СПИСОК ЕКІПАЖУ (The Crew) ---
      # GET /api/v1/users
      def index
        authorize User
        scope = policy_scope(User).order(last_seen_at: :desc, id: :desc)

        respond_to do |format|
          format.json do
            pagy, users = pagy(scope)
            render json: {
              data: UserBlueprint.render_as_hash(users, view: :crew),
              pagy: pagy_metadata(pagy)
            }
          end
          format.html do
            @pagy, @users = pagy(scope)
            render_dashboard(
              title: "Crew Management // The Clan",
              component: Users::Index.new(users: @users, pagy: @pagy)
            )
          end
        end
      end

      # --- ПРОФІЛЬ УЧАСНИКА ---
      # GET /api/v1/users/:id
      def show
        @user = policy_scope(User).find(params[:id])
        authorize @user

        respond_to do |format|
          format.json do
            render json: UserBlueprint.render(@user, view: :crew)
          end
          format.html do
            render_dashboard(
              title: "Profile // #{@user.first_name}",
              component: Users::Profile.new(
                user: @user,
                maintenance_count: @user.maintenance_records.count,
                active_identities: @user.identities.active.to_a,
                codex_fraction: @user.codex_fraction
              )
            )
          end
        end
      end

      # --- ПРОФІЛЬ "Я" (Neural Link) ---
      # GET /api/v1/users/me
      def me
        @user = current_user
        authorize @user

        respond_to do |format|
          format.json do
            render json: UserBlueprint.render(@user, view: :profile)
          end
          format.html do
            render_dashboard(
              title: "Profile // #{@user.first_name}",
              component: Users::Profile.new(
                user: @user,
                maintenance_count: @user.maintenance_records.count,
                active_identities: @user.identities.active.to_a,
                codex_fraction: @user.codex_fraction
              )
            )
          end
        end
      end
    end
  end
end
