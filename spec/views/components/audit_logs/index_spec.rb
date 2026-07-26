# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogs::Index do
  def mock_user(name: "Ada Lovelace")
    OpenStruct.new(full_name: name)
  end

  def mock_log(id: 1, action: "create", auditable_type: "Tree", auditable_id: 99,
               user: nil, created_at: Time.current)
    log = OpenStruct.new(
      id: id,
      action: action,
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      user: user,
      created_at: created_at
    )
    log.define_singleton_method(:model_name) { ActiveModel::Name.new(AuditLog) }
    log.define_singleton_method(:to_key) { [ id ] }
    log.define_singleton_method(:to_param) { id.to_s }
    log
  end

  let(:log_with_user)    { mock_log(id: 1, action: "update", auditable_type: "Tree", auditable_id: 7, user: mock_user) }
  let(:log_without_user) { mock_log(id: 2, action: "destroy", auditable_type: nil, auditable_id: nil, user: nil) }
  let(:logs)             { [ log_with_user, log_without_user ] }
  let(:html)             { render_component(logs: logs, pagy: mock_pagy(count: 63)) }

  describe "header" do
    it "renders the Watcher heading" do
      expect(html).to include("The Watcher")
    end

    it "renders the Audit Log label" do
      expect(html).to include("Audit Log")
    end

    it "renders record count from pagy" do
      expect(html).to include("Records:")
      expect(html).to include("63")
    end
  end

  describe "table headers" do
    it "renders Timestamp column" do
      expect(html).to include("Timestamp")
    end

    it "renders User column" do
      expect(html).to include("User")
    end

    it "renders Action column" do
      expect(html).to include("Action")
    end

    it "renders Target column" do
      expect(html).to include("Target")
    end
  end

  describe "log rows" do
    it "renders user full name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders System for logs without a user" do
      expect(html).to include("System")
    end

    it "renders auditable type and id" do
      expect(html).to include("Tree #7")
    end

    it "renders Inspect link" do
      expect(html).to include("Inspect")
    end

    it "renders aria-label with log id" do
      expect(html).to include("Inspect audit log #1")
    end
  end

  describe "empty state" do
    it "renders empty state when no logs" do
      html = render_component(logs: [], pagy: mock_pagy(count: 0))
      expect(html).to include("No audit events recorded")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end
  end
end
