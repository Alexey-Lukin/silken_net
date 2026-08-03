# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settings::Show do
  def mock_org(name: "Forest Org", billing_email: "billing@org.org",
               crypto_public_address: "0xABCDEF1234",
               alert_threshold_critical_z: 2.5, ai_sensitivity: 0.7,
               id: 1, created_at: 2.years.ago, updated_at: 1.hour.ago,
               logo_attached: false, error_messages: [])
    logo = double("logo", attached?: logo_attached, filename: ActiveStorage::Filename.new("logo.png"))
    OpenStruct.new(
      # [SEC.25] Контролер передає сюди справжню `Organization` — ту саму, чиї
      # `errors` він щойно наповнив невдалим `update`. Доти фікстура цього не
      # знала, тобто оголошувала світ, у якому дефект «форма мовчить на 422»
      # неможливий за побудовою (`04_06 §B.2` BP #14).
      errors: double("errors", full_messages: error_messages),
      name: name,
      billing_email: billing_email,
      crypto_public_address: crypto_public_address,
      alert_threshold_critical_z: alert_threshold_critical_z,
      ai_sensitivity: ai_sensitivity,
      id: id,
      created_at: created_at,
      updated_at: updated_at,
      logo: logo
    )
  end

  def render_component(organization:)
    ApplicationController.renderer.render(
      component_class.new(organization: organization),
      layout: false
    )
  end

  let(:org) { mock_org }
  let(:html) { render_component(organization: org) }

  describe "settings form" do
    it "renders the Configuration heading" do
      expect(html).to include("Configuration")
    end

    it "renders the form action to settings_path" do
      expect(html).to include("/settings")
    end

    it "renders a PATCH form via hidden method" do
      expect(html).to include('value="patch"')
    end
  end

  describe "name field" do
    it "renders the organization name input" do
      expect(html).to include('name="organization[name]"')
    end

    it "pre-fills the current name" do
      expect(html).to include("Forest Org")
    end
  end

  describe "billing email field" do
    it "renders the billing email input" do
      expect(html).to include('name="organization[billing_email]"')
    end

    it "pre-fills the current billing email" do
      expect(html).to include("billing@org.org")
    end

    it "renders the input without a pre-filled value when billing_email is nil" do
      org = mock_org(billing_email: nil)
      rendered = render_component(organization: org)
      expect(rendered).to include('name="organization[billing_email]"')
    end
  end

  describe "crypto address field" do
    it "renders the crypto public address input" do
      expect(html).to include('name="organization[crypto_public_address]"')
    end

    it "pre-fills the crypto address" do
      expect(html).to include("0xABCDEF1234")
    end
  end

  describe "logo upload" do
    it "renders the Organization Logo field" do
      expect(html).to include("Organization Logo")
    end

    it "renders a file input for the logo" do
      expect(html).to include('name="organization[logo]"')
    end
  end

  describe "identity vault section" do
    it "renders the On-Chain Identity Vault heading" do
      expect(html).to include("On-Chain Identity Vault")
    end

    it "renders billing contact in the vault" do
      expect(html).to include("billing@org.org")
    end
  end

  describe "update button" do
    it "renders the Update Settings button" do
      expect(html).to include("Update Settings")
    end
  end

  describe "alert threshold and AI sensitivity fields" do
    it "renders alert_threshold_critical_z field" do
      expect(html).to include('name="organization[alert_threshold_critical_z]"')
    end

    it "renders ai_sensitivity field" do
      expect(html).to include('name="organization[ai_sensitivity]"')
    end
  end

  describe "logo attached" do
    it "renders current logo filename when attached" do
      org = mock_org(logo_attached: true)
      html = render_component(organization: org)
      expect(html).to include("Current: logo.png")
    end

    it "does not render current logo filename when not attached" do
      expect(html).not_to include("Current:")
    end
  end
end
