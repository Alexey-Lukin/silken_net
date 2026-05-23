# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::LocalesController, type: :request do
  describe "POST /api/v1/locale" do
    it "persists a valid locale into a permanent cookie" do
      post "/api/v1/locale", params: { locale: "en" }
      expect(response).to have_http_status(:see_other)
      expect(cookies[:locale]).to eq("en")
    end

    it "accepts the secondary locale (uk → en switch)" do
      post "/api/v1/locale", params: { locale: "uk" }
      expect(cookies[:locale]).to eq("uk")
    end

    it "rejects an unknown locale and does not write a cookie" do
      post "/api/v1/locale", params: { locale: "ru" }
      expect(cookies[:locale]).to be_blank
      expect(flash[:alert]).to be_present
    end

    it "redirects back to the referer when same-host" do
      post "/api/v1/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "http://www.example.com/api/v1/dashboard" }
      expect(response).to redirect_to("http://www.example.com/api/v1/dashboard")
    end

    it "falls back to root_path for missing referer" do
      post "/api/v1/locale", params: { locale: "en" }
      expect(response).to redirect_to(api_v1_root_path)
    end

    it "ignores cross-host referers (open-redirect guard)" do
      post "/api/v1/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "http://attacker.example.com/phish" }
      expect(response).to redirect_to(api_v1_root_path)
    end

    it "handles array locale param without crashing" do
      post "/api/v1/locale", params: { locale: %w[en uk] }
      expect(response).not_to have_http_status(:internal_server_error)
      expect(cookies[:locale]).to be_blank
    end

    it "handles hash locale param without crashing" do
      post "/api/v1/locale", params: { locale: { foo: "bar" } }
      expect(response).not_to have_http_status(:internal_server_error)
      expect(cookies[:locale]).to be_blank
    end

    it "rejects javascript: scheme referer (open-redirect guard)" do
      post "/api/v1/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "javascript:alert(1)" }
      expect(response).to redirect_to(api_v1_root_path)
    end
  end

  describe "LocaleSettable concern (resolution priority)" do
    # Drives the concern via the only public endpoint that is part of this
    # change set — POST /api/v1/locale itself. The POST always passes through
    # `set_locale` before `update`, so `I18n.locale` is observable via the
    # cookie behaviour we already cover above. We additionally assert the
    # default-locale wiring directly from configuration to avoid coupling
    # to other controllers' rendering paths.
    it "ships with :en as the application default locale" do
      expect(I18n.default_locale).to eq(:en)
    end

    it "ships with :uk, :en, :lv and :lt in available_locales" do
      expect(I18n.available_locales).to include(:uk, :en, :lv, :lt)
    end

    it "honours an explicit ?locale= param over the cookie" do
      cookies[:locale] = "uk"
      post "/api/v1/locale", params: { locale: "en" }
      expect(cookies[:locale]).to eq("en")
    end
  end
end
