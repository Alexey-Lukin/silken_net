# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::UsersController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:subscriber) { create(:user, :subscriber, organization: organization) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:subscriber_token) { subscriber.generate_token_for(:api_access) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:subscriber_headers) { { "Authorization" => "Bearer #{subscriber_token}" } }

  describe "GET /users" do
    let!(:extra_user) { create(:user, :forester, organization: organization) }

    context "when as JSON" do
      it "returns org users for admin" do
        get "/users", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body).to have_key("data")
        expect(body).to have_key("pagy")

        ids = body["data"].map { |u| u["id"] }
        expect(ids).to include(admin.id, extra_user.id)
      end

      it "includes pagination metadata" do
        get "/users", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        meta = response.parsed_body["pagy"]
        expect(meta).to include("page", "limit", "count", "pages")
      end
    end

    context "when as HTML" do
      # 🔴 Цей приклад ІСНУВАВ і був зелений усі ті роки, поки «View logs» стояв
      # `href: "#"`: мертвий лінк сторінку не ламає, тож 200 був чесний. Пін на
      # СТАТУС не є піном на вміст — саме тому ціль дії потребує окремого
      # твердження ([UI.7], `04_06 §A.2` правило 10а).
      it "renders the dashboard page" do
        get "/users", headers: admin_headers
        expect(response).to have_http_status(:ok)
      end

      it "points the audit link at that user's own slice of the log" do
        get "/users", headers: admin_headers.merge("Accept" => "text/html")

        expect(response.body).to include(audit_logs_path(user_id: extra_user.id))
        expect(response.body).not_to include('href="#"')
      end
    end

    it "returns 403 for non-admin users" do
      get "/users", headers: subscriber_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/users", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /users/:id" do
    let!(:extra_user) { create(:user, :forester, organization: organization) }

    context "when as JSON" do
      it "returns a specific user from the same organization" do
        get "/users/#{extra_user.id}", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body["id"]).to eq(extra_user.id)
        expect(body["first_name"]).to eq(extra_user.first_name)
      end

      it "works for non-admin users viewing org members" do
        get "/users/#{admin.id}", headers: subscriber_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body["id"]).to eq(admin.id)
      end
    end

    context "when as HTML" do
      # 🔴 [TEST.12 вісь D, друга група присуду D3] Сторінка несе `@user` із контролера,
      # тож смок на 200 сліпий там само, де сліпа компонентна спека (та рендерить повз
      # маршрутизатор і повз викликача). Пін на email, бо це ЄДИНЕ поле профілю, яке
      # не має `presence`-валідації-двійника й приходить рівно з переданого запису.
      it "друкує профіль ЗАПИТАНОГО користувача" do
        get "/users/#{extra_user.id}", headers: admin_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(extra_user.email_address)
      end
    end

    it "returns 404 for a user from another organization" do
      other_org = create(:organization)
      other_user = create(:user, organization: other_org)

      get "/users/#{other_user.id}", headers: subscriber_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      get "/users/#{admin.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /users/me" do
    context "when as JSON" do
      it "returns the current user's profile" do
        get "/users/me", headers: subscriber_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body["email_address"]).to eq(subscriber.email_address)
      end

      it "works for admin users too" do
        get "/users/me", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body["email_address"]).to eq(admin.email_address)
      end
    end

    context "when as HTML" do
      # ⊥ Той самий компонент, що в `show`, але ІНША проводка: тут `@user` береться
      # не з `params[:id]`, а з `current_user`. Саме тому пін мусить називати
      # ВЛАСНИКА токена — інакше підміна одного тракту на інший лишилась би зеленою.
      # ⚠️ Другий користувач НЕОБХІДНИЙ, і це не надмірність — перевірено мутацією,
      # що ПРОЙШЛА: з одним записом у БД підміна `@user` на «будь-кого іншого»
      # віддає `nil` і падає на фолбек, тобто пін мовчить на найправдоподібнішій
      # регресії. Розрізняє лише ПАРА «свій ⊥ чужий».
      it "друкує профіль ВЛАСНИКА токена, а не сусіда" do
        stranger = create(:user, :forester, organization: organization)

        get "/users/me", headers: subscriber_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(subscriber.email_address)
        expect(response.body).not_to include(stranger.email_address)
      end
    end

    it "returns 401 without authentication" do
      get "/users/me", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
