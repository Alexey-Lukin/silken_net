# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogWorker, type: :worker do
  describe "#perform" do
    it "creates an audit log record from attributes" do
      user = create(:user)
      attrs = {
        "user_id" => user.id,
        "organization_id" => user.organization_id,
        "action" => "login",
        "ip_address" => "203.0.113.42",
        "user_agent" => "Mozilla/5.0",
        "metadata" => { "source" => "api" }
      }

      expect { described_class.new.perform(attrs) }
        .to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.action).to eq("login")
      expect(log.ip_address).to eq("203.0.113.42")
      expect(log.user_agent).to eq("Mozilla/5.0")
      expect(log.metadata).to eq("source" => "api")
    end

    it "logs error for invalid attributes without raising" do
      attrs = { "action" => nil, "user_id" => 0, "organization_id" => 0 }

      expect(Rails.logger).to receive(:error).with(/Невалідний запис/)
      expect { described_class.new.perform(attrs) }.not_to raise_error
    end
  end
end
