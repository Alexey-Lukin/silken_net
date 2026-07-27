# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # [I18N.1] Cookie тримає вибір для БРАУЗЕРА; колонка — для того, що з браузера
    # не видно. Пошта йде з Sidekiq, де ані cookie, ані сесії немає, тож без цього
    # запису `users.locale` лишався б NULL назавжди, а `in_locale_of` у мейлері —
    # декоративним. Саме цей клас («колонка є, заповнювати нікому») тут і пінимо.
    describe "persisting the choice for a signed-in user" do
      let(:user) { create(:user, locale: nil) }

      def sign_in!
        post "/api/v1/login", params: { email: user.email_address, password: "password12345" }
      end

      it "stores the chosen locale on the user record" do
        sign_in!

        expect { post "/api/v1/locale", params: { locale: "uk" } }
          .to change { user.reload.locale }.from(nil).to("uk")
      end

      it "leaves an anonymous visitor's switch working without persisting anything" do
        expect { post "/api/v1/locale", params: { locale: "uk" } }
          .not_to change(User, :count)

        expect(cookies[:locale]).to eq("uk")
        expect(user.reload.locale).to be_nil
      end

      # Guard дзеркалить [SEC.16]: сам по собі `session[:user_id]` не є доказом —
      # salt-stamp гасне при зміні пароля. Без цієї перевірки запис у БД став би
      # тихим обходом salt-прив'язки.
      it "does not persist when the session salt-stamp no longer matches" do
        sign_in!
        user.update!(password: "brand-new-password-123", password_confirmation: "brand-new-password-123")

        expect { post "/api/v1/locale", params: { locale: "lv" } }
          .not_to change { user.reload.locale }
      end

      it "does not write when the choice already matches the stored one" do
        user.update!(locale: "uk")
        sign_in!

        expect { post "/api/v1/locale", params: { locale: "uk" } }
          .not_to change { user.reload.updated_at }
      end
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
    let(:test_stub_class) do
      base = Class.new do
        attr_accessor :params, :cookies, :request
        define_singleton_method(:before_action) { |*| } # stub out controller DSL
      end
      base.send(:include, LocaleSettable)
      base
    end

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


    it "uses request#preferred_language when available and produces a known locale" do
      stub_request = Object.new
      stub_request.define_singleton_method(:preferred_language) { |_avail| "uk" }

      instance = test_stub_class.new
      instance.params = {}
      instance.cookies = {}
      instance.request = stub_request

      expect(instance.send(:resolve_locale)).to eq(:uk)
    end

    it "swallows StandardError from preferred_language and falls back to the default" do
      stub_request = Object.new
      stub_request.define_singleton_method(:preferred_language) { |_avail| raise StandardError, "bad header" }

      instance = test_stub_class.new
      instance.params = {}
      instance.cookies = {}
      instance.request = stub_request

      expect(instance.send(:resolve_locale)).to eq(I18n.default_locale)
    end
  end
end
