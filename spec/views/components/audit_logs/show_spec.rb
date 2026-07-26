# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogs::Show do
  def mock_user(full_name: "Ada Lovelace", email_address: "ada@silken.net", role: "admin")
    OpenStruct.new(full_name: full_name, email_address: email_address, role: role)
  end

  def mock_log(id: 1, action: "update", auditable_type: "Tree", auditable_id: 42,
               user: nil, metadata: {}, created_at: Time.current)
    log = OpenStruct.new(
      id: id,
      action: action,
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      user: user,
      metadata: metadata,
      created_at: created_at
    )
    log.define_singleton_method(:model_name) { ActiveModel::Name.new(AuditLog) }
    log.define_singleton_method(:to_key) { [ id ] }
    log.define_singleton_method(:to_param) { id.to_s }
    log
  end

  let(:user) { mock_user }
  let(:log)  { mock_log(id: 5, action: "update", user: user, metadata: { "reason" => "correction" }) }
  let(:html) { render_component(log: log) }

  describe "header section" do
    it "renders Audit Event Record label" do
      expect(html).to include("Audit Event Record")
    end

    it "renders log action as heading" do
      expect(html).to include("update")
    end

    it "renders log id and timestamp" do
      expect(html).to include("#5")
    end
  end

  describe "details table" do
    it "renders Action field" do
      expect(html).to include("Action")
    end

    it "renders Performed By field with user name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders Target Type field" do
      expect(html).to include("Tree")
    end

    it "renders Target ID field" do
      expect(html).to include("42")
    end
  end

  describe "metadata panel" do
    it "renders Event Metadata heading" do
      expect(html).to include("Event Metadata")
    end

    it "renders metadata key-value pairs" do
      expect(html).to include("reason")
      expect(html).to include("correction")
    end

    it "renders empty metadata notice when no metadata" do
      log_no_meta = mock_log(metadata: {})
      html = render_component(log: log_no_meta)
      expect(html).to include("No additional metadata")
    end
  end

  describe "actor info" do
    it "renders Actor Identity heading" do
      expect(html).to include("Actor Identity")
    end

    it "renders actor full name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders actor email" do
      expect(html).to include("ada@silken.net")
    end

    it "renders actor role" do
      expect(html).to include("admin")
    end

    it "renders System actor notice for system logs" do
      system_log = mock_log(user: nil)
      html = render_component(log: system_log)
      expect(html).to include("System actor")
    end
  end

  describe "target info" do
    it "renders Auditable Target heading" do
      expect(html).to include("Auditable Target")
    end

    it "renders auditable type" do
      expect(html).to include("Tree")
    end

    it "renders auditable id" do
      expect(html).to include("42")
    end

    it "renders no specific target notice when auditable_type is blank" do
      log_no_target = mock_log(auditable_type: nil, auditable_id: nil)
      html = render_component(log: log_no_target)
      expect(html).to include("No specific target")
    end
  end
end
