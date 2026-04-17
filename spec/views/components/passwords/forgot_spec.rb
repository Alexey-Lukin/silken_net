# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passwords::Forgot do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  let(:html) { render_component(flash_alert: nil, flash_notice: nil) }

  describe "header" do
    it "renders Recovery heading" do
      expect(html).to include("Recovery")
    end

    it "renders Password Reset Protocol subtitle" do
      expect(html).to include("Password Reset Protocol")
    end
  end

  describe "form fields" do
    it "renders Email Address label" do
      expect(html).to include("Email Address")
    end

    it "renders email input field" do
      expect(html).to include('type="email"')
    end

    it "renders email placeholder" do
      expect(html).to include("architect@silken.net")
    end
  end

  describe "submit button" do
    it "renders SEND RESET LINK button" do
      expect(html).to include("SEND RESET LINK")
    end
  end

  describe "back to login link" do
    it "renders Back to Login Portal link" do
      expect(html).to include("Back to Login Portal")
    end
  end

  describe "flash messages" do
    it "renders alert message when flash_alert is present" do
      html = render_component(flash_alert: "Email not found", flash_notice: nil)
      expect(html).to include("Email not found")
    end

    it "renders notice message when flash_notice is present" do
      html = render_component(flash_alert: nil, flash_notice: "Reset link sent")
      expect(html).to include("Reset link sent")
    end

    it "does not render flash div when both are nil" do
      expect(html).not_to include("Reset link sent")
      expect(html).not_to include("Email not found")
    end
  end

  describe "form action" do
    it "posts to the forgot password path" do
      expect(html).to include("forgot_password")
    end
  end

  describe "structure" do
    it "renders the form element" do
      expect(html).to include("<form")
    end
  end
end
