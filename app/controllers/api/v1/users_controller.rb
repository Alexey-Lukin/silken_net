# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      # --- СПИСОК ЕКІПАЖУ (The Crew) ---
      # GET /users
      # [UI.7] `authorize` вирішує, ЧИ можна дивитись список (роль), а
      # `acting_organization!` — ЧОГО саме (організація запиту). Порядок несучий:
      # інвестор без права дістає 403 незалежно від контексту, а admin без
      # організації — 422 `no_organization`, як усі тенантні поверхні (`04_03 §3.1`,
      # політика (1)). Доти цей екшен був ТРЕТЬОЮ поведінкою: `policy_scope`
      # фільтрував по `IS NULL` і чесно віддавав платформених користувачів, кожен
      # рядок якого `show?` нижче відхиляв — список, який неможливо відкрити.
      def index
        authorize User
        acting_organization!
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
              title: I18n.t("users.index_title"),
              component: Users::Index.new(users: @users, pagy: @pagy)
            )
          end
        end
      end

      # --- ПРОФІЛЬ УЧАСНИКА ---
      # GET /users/:id
      def show
        acting_organization!
        @user = policy_scope(User).find(params[:id])
        authorize @user

        respond_to do |format|
          format.json do
            render json: UserBlueprint.render(@user, view: :crew)
          end
          format.html do
            render_dashboard(
              title: I18n.t("users.show_title", name: @user.first_name),
              component: Users::Profile.new(
                user: @user,
                maintenance_count: @user.maintenance_records.count
              )
            )
          end
        end
      end

      # --- ПРОФІЛЬ "Я" (Neural Link) ---
      # GET /users/me
      def me
        @user = current_user
        authorize @user

        respond_to do |format|
          format.json do
            render json: UserBlueprint.render(@user, view: :profile)
          end
          format.html do
            render_dashboard(
              title: I18n.t("users.show_title", name: @user.first_name),
              component: Users::Profile.new(
                user: @user,
                maintenance_count: @user.maintenance_records.count
              )
            )
          end
        end
      end
    end
  end
end
