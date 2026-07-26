# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passwords::Reset do
  let(:token) { "abc123securetoken" }
  let(:html)  { render_component(token: token, flash_alert: nil) }

  describe "header" do
    it "renders New Key heading" do
      expect(html).to include("New Key")
    end

    it "renders Set New Access Code subtitle" do
      expect(html).to include("Set New Access Code")
    end
  end

  describe "form fields" do
    it "renders password input field" do
      expect(html).to include('type="password"')
    end

    it "renders New Password label" do
      expect(html).to include("New Password")
    end

    it "renders password_confirmation field" do
      expect(html).to include("password_confirmation")
    end

    it "renders Confirm New Password label" do
      expect(html).to include("Confirm New Password")
    end

    it "renders hidden token field" do
      expect(html).to include('name="token"')
      expect(html).to include("abc123securetoken")
    end

    it "renders hidden _method patch override" do
      expect(html).to include('value="patch"')
    end
  end

  describe "submit button" do
    it "renders SET NEW PASSWORD button" do
      expect(html).to include("SET NEW PASSWORD")
    end
  end

  describe "back to login link" do
    it "renders Back to Login Portal link" do
      expect(html).to include("Back to Login Portal")
    end
  end

  describe "flash messages" do
    it "renders alert message when flash_alert is present" do
      html = render_component(token: token, flash_alert: "Token expired")
      expect(html).to include("Token expired")
    end

    it "does not render alert div when flash_alert is nil" do
      expect(html).not_to include("Token expired")
    end
  end

  describe "form structure" do
    it "renders form element" do
      expect(html).to include("<form")
    end

    it "posts to reset_password path" do
      expect(html).to include("reset_password")
    end
  end
end
