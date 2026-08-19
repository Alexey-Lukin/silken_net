# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountSecurity::MfaSetup do
  # Реальний User (не OpenStruct): компонент читає `otp_provisioning_uri` —
  # ДЕРИВАЦІЮ над секретом, і мок із «правильними полями» рендерив би порожнечу
  # (сьома вісь TEST.12: fixture right by name, blind by derivation).
  def build_user
    User.new(email_address: "mfa@example.com", otp_secret: ROTP::Base32.random)
  end

  def render_component(user: build_user, error: nil)
    ApplicationController.renderer.render(
      described_class.new(user: user, error: error),
      layout: false
    )
  end

  describe "rendering" do
    let(:html) { render_component }

    it "renders the QR as inline SVG (offline, CSP-clean)" do
      expect(html).to include("<svg")
      # Жодного зовнішнього QR-сервісу: картинок нема взагалі, QR — інлайн-вектор.
      expect(html).not_to include("<img")
    end

    it "shows the manual-entry secret grouped by four" do
      expect(html).to match(/[A-Z2-7]{4} [A-Z2-7]{4}/)
    end

    it "submits the confirmation code via PATCH to the setup path" do
      expect(html).to include('action="/account_security/mfa_setup"')
      expect(html).to include('name="otp_code"')
    end

    it "labels the flow in the viewer's locale (uk)" do
      uk = I18n.with_locale(:uk) { render_component }
      expect(uk).to include("Підключення автентифікатора")
      expect(uk).to include("Активувати MFA")
    end
  end

  describe "error branch" do
    it "renders the current submit error with role=alert" do
      html = render_component(error: "no match")
      expect(html).to include('role="alert"')
      expect(html).to include("no match")
    end

    it "renders no alert node without an error" do
      expect(render_component).not_to include('role="alert"')
    end
  end

  describe "accessibility" do
    it "associates the code label with its field" do
      expect(render_component).to include('<label for="otp_code"')
    end

    it "keeps focus-visible ring on the activate button" do
      expect(render_component).to include("focus-visible:ring-gaia-primary-strong")
    end
  end
end
