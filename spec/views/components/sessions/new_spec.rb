# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::New do

  let(:html) { render_component(flash_alert: nil, flash_notice: nil) }

  describe "portal header" do
    it "renders Citadel heading" do
      expect(html).to include("Citadel")
    end

    it "renders Establishing Neural Link subtitle" do
      expect(html).to include("Establishing Neural Link")
    end
  end

  describe "form fields" do
    it "renders email input field" do
      expect(html).to include('type="email"')
    end

    it "renders Identity label for email" do
      expect(html).to include("Identity (Email)")
    end

    it "renders password input field" do
      expect(html).to include('type="password"')
    end

    it "renders Access Code label for password" do
      expect(html).to include("Access Code (Password)")
    end

    it "renders AUTHENTICATE submit button" do
      expect(html).to include("AUTHENTICATE")
    end
  end

  describe "forgot password link" do
    it "renders Forgot Access Code link" do
      expect(html).to include("Forgot Access Code?")
    end
  end

  describe "OAuth provider buttons" do
    it "renders Google provider button" do
      expect(html).to include("Google")
    end

    it "renders Facebook provider button" do
      expect(html).to include("Facebook")
    end

    it "renders LinkedIn provider button" do
      expect(html).to include("LinkedIn")
    end

    it "renders Twitter provider button" do
      expect(html).to include("Twitter")
    end

    it "renders provider auth paths" do
      expect(html).to include("/auth/google_oauth2")
    end
  end

  describe "flash messages" do
    it "renders alert message when flash_alert is present" do
      html = render_component(flash_alert: "Invalid credentials", flash_notice: nil)
      expect(html).to include("Invalid credentials")
    end

    it "renders notice message when flash_notice is present" do
      html = render_component(flash_alert: nil, flash_notice: "Check your email")
      expect(html).to include("Check your email")
    end

    it "does not render alert div when flash_alert is nil" do
      expect(html).not_to include('role="alert"')
    end
  end

  describe "security footer" do
    it "renders AES-256 Enabled text" do
      expect(html).to include("AES-256")
    end
  end
end
