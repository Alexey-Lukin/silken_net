# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::MfaChallenge do
  def render_component(flash_alert: nil)
    ApplicationController.renderer.render(
      described_class.new(flash_alert: flash_alert),
      layout: false
    )
  end

  describe "rendering" do
    let(:html) { render_component }

    it "posts to the challenge path" do
      expect(html).to include('action="/login/mfa"')
    end

    it "renders the TOTP field with one-time-code autocomplete" do
      expect(html).to include('name="otp_code"')
      expect(html).to include('autocomplete="one-time-code"')
    end

    it "renders the recovery field in a native collapsible, no JS" do
      expect(html).to include("<details")
      expect(html).to include('name="recovery_code"')
      expect(html).not_to include("data-controller")
    end

    it "labels both factors distinctly (uk)" do
      uk = I18n.with_locale(:uk) { render_component }
      expect(uk).to include("Код автентифікатора")
      expect(uk).to include("Recovery-код")
    end
  end

  describe "flash alert" do
    it "renders the current submit error with role=alert" do
      html = render_component(flash_alert: "boom")
      expect(html).to include('role="alert"')
      expect(html).to include("boom")
    end

    it "renders no alert node when there is nothing to say" do
      expect(render_component).not_to include('role="alert"')
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "wraps the page in a main landmark" do
      expect(html).to include('role="main"')
    end

    it "associates labels with their fields" do
      expect(html).to include('<label for="otp_code"')
    end
  end
end
