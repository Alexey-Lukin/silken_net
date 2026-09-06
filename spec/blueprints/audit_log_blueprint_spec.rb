# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogBlueprint, type: :model do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, first_name: "Olena", last_name: "Kovalenko", role: :admin, organization: organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:audit_log) do
    create(:audit_log, :with_auditable, user: user, organization: organization,
                                        action: "system_parameter_changed",
                                        ip_address: "192.168.1.42",
                                        user_agent: "Mozilla/5.0 (X11; Linux)")
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(audit_log, view: :index)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(audit_log.id)
    end

    it "includes action and auditable info" do
      expect(parsed["action"]).to eq("system_parameter_changed")
      expect(parsed["auditable_type"]).to be_present
      expect(parsed["auditable_id"]).to be_present
    end

    it "includes metadata" do
      expect(parsed["metadata"]).to be_a(Hash)
    end

    it "includes created_at" do
      expect(parsed).to have_key("created_at")
    end

    it "includes user association in :crew view" do
      user_data = parsed["user"]
      expect(user_data).to be_a(Hash)
      expect(user_data["first_name"]).to eq("Olena")
      expect(user_data["last_name"]).to eq("Kovalenko")
      expect(user_data["role"]).to eq("admin")
      expect(user_data["full_name"]).to eq("Olena Kovalenko")
    end

    it "excludes show-only fields" do
      expect(parsed).not_to have_key("ip_address")
      expect(parsed).not_to have_key("user_agent")
      expect(parsed).not_to have_key("chain_hash")
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(audit_log, view: :show)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(audit_log.id)
    end

    it "includes action and auditable info" do
      expect(parsed["action"]).to eq("system_parameter_changed")
      expect(parsed["auditable_type"]).to be_present
      expect(parsed["auditable_id"]).to be_present
    end

    it "includes metadata" do
      expect(parsed["metadata"]).to be_a(Hash)
    end

    it "includes security fields" do
      expect(parsed["ip_address"]).to eq("192.168.1.42")
      expect(parsed["user_agent"]).to eq("Mozilla/5.0 (X11; Linux)")
    end

    it "includes chain_hash" do
      expect(parsed["chain_hash"]).to be_a(String)
      expect(parsed["chain_hash"].length).to eq(64)
    end

    it "includes created_at" do
      expect(parsed).to have_key("created_at")
    end

    # 🔴 [SEC.36 2026-09-06] Пін ПЕРЕВЕРНУТО, і в цьому вся його суть. Доти він
    # ВИМАГАВ `mfa_enabled` і `has_password` у чужому записі журналу — тобто
    # зелений колір стеріг рівно ту переекспозицію, яку пункт і знайшов. Носій
    # не був хибним: він чесно фіксував намір, який виявився неправильним.
    # Тепер він стереже зворотний бік — щоб `:profile` (вигляд «про СЕБЕ»,
    # `GET /users/me`) не повернувся сюди мовчки.
    it "gives the actor the :crew view — never the self-facing :profile" do
      user_data = parsed["user"]
      expect(user_data).to be_a(Hash)
      expect(user_data["first_name"]).to eq("Olena")
      expect(user_data["last_name"]).to eq("Kovalenko")
      expect(user_data["full_name"]).to eq("Olena Kovalenko")
      expect(user_data["role"]).to eq("admin")

      # Ідентифікатор лишається — саме він робить звуження оборотним для
      # законного споживача (адреса резолвиться окремим запитом).
      expect(user_data["id"]).to eq(user.id)

      # Три поля, що не мають дому в чужому записі: два — безпекова постава
      # колеги, третє — його пошта, яку HTML-панель показує, а JSON більше ні.
      expect(user_data).not_to have_key("mfa_enabled")
      expect(user_data).not_to have_key("has_password")
      expect(user_data).not_to have_key("email_address")
    end
  end

  describe "audit_log without auditable" do
    let(:audit_log_no_auditable) do
      create(:audit_log, user: user, organization: organization)
    end

    it "renders nil auditable fields in :index" do
      parsed = JSON.parse(described_class.render(audit_log_no_auditable, view: :index))
      expect(parsed["auditable_type"]).to be_nil
      expect(parsed["auditable_id"]).to be_nil
    end
  end

  describe "collection rendering" do
    let!(:logs) do
      create_list(:audit_log, 3, user: user, organization: organization)
    end

    it "renders an array of audit logs" do
      parsed = JSON.parse(described_class.render(logs, view: :index))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed).to all(include("action", "user"))
    end
  end
end
