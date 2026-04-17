# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Settings do

  def mock_user(id: 1, email_address: "ada@silken.net", phone_number: "+380501234567",
               telegram_chat_id: "123456789", push_token: nil)
    user = OpenStruct.new(
      id: id,
      email_address: email_address,
      phone_number: phone_number,
      telegram_chat_id: telegram_chat_id,
      push_token: push_token
    )
    user.define_singleton_method(:model_name) { ActiveModel::Name.new(User) }
    user.define_singleton_method(:to_key) { [id] }
    user.define_singleton_method(:to_param) { id.to_s }
    user
  end

  let(:user) { mock_user }
  let(:html) { render_component(user: user) }

  describe "header section" do
    it "renders Neural Web heading" do
      expect(html).to include("Neural Web")
    end

    it "renders Notification Channels subtitle" do
      expect(html).to include("Notification Channels")
    end
  end

  describe "form fields" do
    it "renders email field as disabled" do
      expect(html).to include("ada@silken.net")
      expect(html).to include("disabled")
    end

    it "renders phone number field" do
      expect(html).to include("phone_number")
      expect(html).to include("+380501234567")
    end

    it "renders telegram_chat_id field" do
      expect(html).to include("telegram_chat_id")
      expect(html).to include("123456789")
    end

    it "renders push_token field" do
      expect(html).to include("push_token")
    end

    it "renders submit button" do
      expect(html).to include("Save Channels")
    end
  end

  describe "channel status indicators" do
    it "renders Email channel status" do
      expect(html).to include("Email")
    end

    it "renders SMS / Phone channel status" do
      expect(html).to include("SMS")
    end

    it "renders Telegram channel status" do
      expect(html).to include("Telegram")
    end

    it "renders Push channel status" do
      expect(html).to include("Push")
    end

    it "shows Connected for configured channels" do
      expect(html).to include("Connected")
    end

    it "shows Not configured for empty push_token" do
      expect(html).to include("Not configured")
    end
  end

  describe "notification types list" do
    it "renders Critical Alerts type" do
      expect(html).to include("Critical")
    end

    it "renders Warning Alerts type" do
      expect(html).to include("Warning")
    end

    it "renders Minting Events type" do
      expect(html).to include("Minting")
    end

    it "renders Slashing Events type" do
      expect(html).to include("Slashing")
    end

    it "renders System Health type" do
      expect(html).to include("System Health")
    end

    it "shows ACTIVE for all notification types" do
      active_count = html.scan("ACTIVE").length
      expect(active_count).to be >= 5
    end
  end

  describe "Active Channels section" do
    it "renders Active Channels heading" do
      expect(html).to include("Active Channels")
    end
  end
end
