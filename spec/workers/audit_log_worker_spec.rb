# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("low")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end

  describe "module inclusion" do
    it "includes Sidekiq::Job" do
      expect(described_class.ancestors).to include(Sidekiq::Job)
    end
  end

  # [ARCH.57] archive=false → chain-only: без outbox-маркера і без Filecoin-піна
  # (security-метадані привілейованих дій не течуть на публічний IPFS).
  describe "#perform with archive=false" do
    it "creates the log without the outbox marker and without FilecoinArchiveWorker" do
      user = create(:user)
      attrs = { "user_id" => user.id, "organization_id" => user.organization_id,
                "action" => "hardware_key_rotated" }

      expect { described_class.new.perform(attrs, false) }
        .to change(AuditLog, :count).by(1)
      expect { described_class.new.perform(attrs, false) }
        .not_to change { FilecoinArchiveWorker.jobs.size }

      expect(AuditLog.last.archive_requested_at).to be_nil
    end
  end

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

    it "enqueues FilecoinArchiveWorker after creating the audit log" do
      user = create(:user)
      attrs = {
        "user_id" => user.id,
        "organization_id" => user.organization_id,
        "action" => "login",
        "ip_address" => "203.0.113.42",
        "user_agent" => "Mozilla/5.0",
        "metadata" => { "source" => "api" }
      }

      described_class.new.perform(attrs)

      log = AuditLog.last
      expect(FilecoinArchiveWorker.jobs.size).to eq(1)
      expect(FilecoinArchiveWorker.jobs.first["args"]).to eq([ log.id ])
    end

    it "logs error for invalid attributes without raising" do
      attrs = { "action" => nil, "user_id" => 0, "organization_id" => 0 }

      allow(Rails.logger).to receive(:error).with(/Невалідний запис/)

      expect { described_class.new.perform(attrs) }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Невалідний запис/)
    end

    it "does not enqueue FilecoinArchiveWorker on failure" do
      attrs = { "action" => nil, "user_id" => 0, "organization_id" => 0 }

      allow(Rails.logger).to receive(:error)
      described_class.new.perform(attrs)

      expect(FilecoinArchiveWorker.jobs).to be_empty
    end

    it "sets correct user_id on the audit log" do
      user = create(:user)
      attrs = {
        "user_id" => user.id,
        "organization_id" => user.organization_id,
        "action" => "password_reset",
        "ip_address" => "10.0.0.1",
        "user_agent" => "SilkenNetMobile/1.0"
      }

      described_class.new.perform(attrs)

      log = AuditLog.last
      expect(log.user_id).to eq(user.id)
      expect(log.organization_id).to eq(user.organization_id)
    end

    it "handles action types from the audit log enum" do
      user = create(:user)
      %w[login logout token_mint token_slash].each do |action|
        attrs = {
          "user_id" => user.id,
          "organization_id" => user.organization_id,
          "action" => action,
          "ip_address" => "10.0.0.1",
          "user_agent" => "Mozilla/5.0"
        }

        expect { described_class.new.perform(attrs) }.to change(AuditLog, :count).by(1)
      end
    end
  end
end
