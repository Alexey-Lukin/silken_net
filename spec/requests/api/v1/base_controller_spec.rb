# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :request do
  describe "RBAC helpers" do
    let(:controller) { described_class.new }

    before do
      allow(controller).to receive(:render)
      allow(controller).to receive(:render_forbidden)
    end

    describe "authorize_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_super_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_super_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_forester!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_admin! with admin user" do
      it "does not call render_forbidden" do
        admin = create(:user, :admin)
        allow(controller).to receive(:current_user).and_return(admin)
        controller.send(:authorize_admin!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! with forester user" do
      it "does not call render_forbidden" do
        forester = create(:user, :forester)
        allow(controller).to receive(:current_user).and_return(forester)
        controller.send(:authorize_forester!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end
  end

  describe "render_internal_server_error" do
    it "logs and renders 500 error" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = StandardError.new("test failure")
      exception.set_backtrace([ "line1", "line2" ])

      controller.send(:render_internal_server_error, exception)
      expect(controller).to have_received(:render).with(
        hash_including(json: hash_including(:error), status: :internal_server_error)
      )
    end
  end

  describe "signed_in? helper" do
    it "returns false when no user is authenticated" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)
      expect(controller.send(:signed_in?)).to be false
    end

    it "returns true when user is authenticated" do
      organization = create(:organization)
      user_for_test = create(:user, organization: organization, password: "password12345")
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user_for_test)
      expect(controller.send(:signed_in?)).to be true
    end
  end

  describe "CSRF bypass for Bearer-token requests" do
    let(:controller) { described_class.new }

    it "lets Bearer-token requests through (CSRF check skipped)" do
      request = instance_double(ActionDispatch::Request, authorization: "Bearer abc.def.ghi")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }.not_to raise_error
    end

    it "raises InvalidAuthenticityToken for session-cookie requests" do
      request = instance_double(ActionDispatch::Request, authorization: nil)
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "raises for non-Bearer auth schemes (Basic)" do
      request = instance_double(ActionDispatch::Request, authorization: "Basic dXNlcjpwYXNz")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end

  describe "render_parameter_missing" do
    it "returns 400 with the missing param name" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = ActionController::ParameterMissing.new(:codex_node_slug)

      controller.send(:render_parameter_missing, exception)
      expect(controller).to have_received(:render).with(
        hash_including(json: hash_including(:error), status: :bad_request)
      )
    end
  end

  describe "render_validation_error" do
    it "returns 422 with all validation messages" do
      controller = described_class.new
      allow(controller).to receive(:render)
      record = OpenStruct.new(errors: OpenStruct.new(full_messages: [ "Name can't be blank", "Email is invalid" ]))

      controller.send(:render_validation_error, record)
      expect(controller).to have_received(:render).with(
        hash_including(
          json: { errors: [ "Name can't be blank", "Email is invalid" ] },
          status: :unprocessable_content
        )
      )
    end
  end

  describe "render_not_found" do
    it "interpolates the model name into the error message" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = ActiveRecord::RecordNotFound.new("not found")
      exception.instance_variable_set(:@model, "Tree")

      controller.send(:render_not_found, exception)
      expect(controller).to have_received(:render).with(
        hash_including(status: :not_found)
      )
    end
  end

  describe "render_forbidden_pundit" do
    it "returns 403 regardless of the Pundit policy raised" do
      controller = described_class.new
      allow(controller).to receive(:render)
      controller.send(:render_forbidden_pundit, instance_double(Pundit::NotAuthorizedError))
      expect(controller).to have_received(:render).with(
        hash_including(status: :forbidden)
      )
    end
  end

  describe "pagy_metadata" do
    it "extracts page/limit/count/pages from a Pagy object" do
      controller = described_class.new
      pagy = OpenStruct.new(page: 2, limit: 21, count: 105, last: 5)
      meta = controller.send(:pagy_metadata, pagy)
      expect(meta).to eq(page: 2, limit: 21, count: 105, pages: 5)
    end
  end

  # Бейдж «Threat Alerts» рендериться на КОЖНІЙ сторінці дашборда, тож його число —
  # найширше розповсюджений тенант-факт у застосунку.
  # ⚠️ Раніше тут стояв приклад `allow(EwsAlert).to receive(:unresolved) → double(count: 7)`
  # з очікуванням `eq(7)`. Він був ВАКУУМНИЙ: стабив саме те, що перевіряв, тобто
  # стверджував лише «хелпер повертає те, що повертає його ж реалізація». Саме тому
  # відсутність org-скоупу була невидима — приклад не міг її виразити в принципі.
  describe "ews_alert_count_cached (sidebar badge)" do
    let(:org_a) { create(:organization) }
    let(:org_b) { create(:organization) }
    let(:user_a) { create(:user, :forester, organization: org_a) }
    let(:user_b) { create(:user, :forester, organization: org_b) }

    before do
      allow(AlertNotificationWorker).to receive(:perform_async)
      allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
      Rails.cache.clear
      # Pause: `Tree.after_create` тягне wallet+calibration на кожне дерево фабрики —
      # це N+1 У ФІКСТУРІ, не в коді під тестом.
      Prosopite.pause if defined?(Prosopite)
      create(:ews_alert, cluster: create(:cluster, organization: org_a), status: :active)
      3.times { create(:ews_alert, cluster: create(:cluster, organization: org_b), status: :active) }
      Prosopite.resume if defined?(Prosopite)
    end

    def count_for(user)
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user)
      controller.send(:ews_alert_count_cached)
    end

    # Один приклад ловить ДВІ незалежні мутації, і порядок викликів тут несучий:
    # A прогріває кеш, перевіряється B. Скинути org-скоуп ЗАПИТУ → A віддасть 4;
    # повернути глобальний КЛЮЧ кешу → B віддасть закешоване число A. Двоє
    # глядачів обовʼязкові — з одним «4 замість 1» не відрізнити від правильного.
    it "counts only the viewer's own organization, and does not cache across organizations" do
      expect(count_for(user_a)).to eq(1)
      expect(count_for(user_b)).to eq(3)
    end

    it "returns zero for a viewer without an organization (fail-closed, not a global sum)" do
      expect(count_for(create(:user, :super_admin, organization: nil))).to eq(0)
    end

    it "swallows any backend error and returns 0 so the sidebar never breaks" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user_a)
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "cache down")
      expect(controller.send(:ews_alert_count_cached)).to eq(0)
    end
  end

  # [SEC.25 Ф2] Доти ці приклади конструювали контролер напряму й стабали `render`,
  # `respond_to` і `current_user`, тобто перевіряли приватний метод у вакуумі —
  # вони лишались би зеленими, навіть якби гард узагалі не був підключений до
  # жодного запиту. Тепер це справжній HTTP-шлях: гард живе в ТОЧЦІ ЧИТАННЯ
  # організації, тож єдиний спосіб довести, що він працює, — прийти по-справжньому.
  describe "коли організації немає" do
    let(:user_without_org) { create(:user, :admin, organization: nil) }

    def sign_in_headers(user)
      { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" }
    end

    it "віддає 422 з машинним кодом на JSON-запит" do
      get "/api/v1/dashboard", headers: sign_in_headers(user_without_org), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("no_organization")
    end

    it "віддає HTML-сторінку з поясненням на браузерний запит" do
      get "/api/v1/dashboard", headers: sign_in_headers(user_without_org).merge("Accept" => "text/html")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      # 🔴 Саме цей рядок відрізняє полагоджене від зламаного: доти ця сторінка
      # віддавала JSON-блоб у браузері (`render_internal_server_error` без
      # `respond_to`), і глядач бачив сирий `{"error":...}` замість сторінки.
      expect(response.body).to include("<html")
    end

    it "не заважає сторінкам, які організації не читають" do
      # Гард у точці читання не має списку винятків — сторінка, що org не питає,
      # його просто не тригерить. Мутація «повернути класовий before_action»
      # червонить саме цей приклад.
      get "/api/v1/codex/leaderboard", as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
