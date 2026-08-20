# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gdpr::DataExportService do
  let(:organization) { create(:organization) }
  let(:user) do
    create(:user, :forester,
           organization: organization,
           first_name: "Оксана", last_name: "Вернидуб",
           phone_number: "+380671112233",
           telegram_chat_id: "tg-777",
           locale: "uk")
  end

  describe "#perform" do
    subject(:export) { described_class.call(user) }

    it "carries the subject's core PII row" do
      expect(export[:user]).to include(
        email_address: user.email_address,
        first_name: "Оксана",
        last_name: "Вернидуб",
        phone_number: "+380671112233",
        telegram_chat_id: "tg-777",
        locale: "uk",
        organization_name: organization.name
      )
    end

    # 🔴 Негативна половина НЕСУЧА: DSAR віддає дані ПРО особу, ніколи секрети
    # автентифікації — їх поява в експорті була б новою витіковою поверхнею.
    it "never exports credentials in any section" do
      json = JSON.generate(export)
      expect(json).not_to include("password_digest")
      expect(json).not_to include("otp_secret")
      expect(json).not_to include("recovery_codes")
      expect(json).not_to include("access_token")
      expect(json).not_to include("refresh_token")
    end

    it "includes the login trail from sessions" do
      user.sessions.create!(ip_address: "203.0.113.7", user_agent: "FieldTablet/1.0")

      trail = described_class.call(user)[:sessions]
      expect(trail.size).to eq(1)
      expect(trail.first).to include(ip_address: "203.0.113.7", user_agent: "FieldTablet/1.0")
    end

    it "includes OAuth profile data but not its tokens" do
      user.identities.create!(
        provider: "google_oauth2", uid: "g-123",
        auth_data: { "name" => "Oksana V", "email" => "ok@example.com" },
        access_token: "secret-token-value"
      )

      identities = described_class.call(user)[:identities]
      expect(identities.first).to include(provider: "google_oauth2", uid: "g-123")
      expect(identities.first[:profile_data]).to include("name" => "Oksana V")
      expect(JSON.generate(identities)).not_to include("secret-token-value")
    end

    it "includes audit rows where the subject is the actor" do
      AuditLog.create!(
        user_id: user.id, organization_id: organization.id,
        action: "acting_organization_switched",
        auditable_type: "Organization", auditable_id: organization.id,
        ip_address: "198.51.100.4", user_agent: "Chrome", metadata: {}
      )

      audit = described_class.call(user)[:audit_trail]
      expect(audit.size).to eq(1)
      expect(audit.first).to include(
        action: "acting_organization_switched", ip_address: "198.51.100.4"
      )
    end

    it "includes authored maintenance records with photo METADATA only" do
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster)
      record = create(:maintenance_record, maintainable: tree, user: user,
                                           action_type: :inspection, performed_at: 2.days.ago,
                                           notes: "Планова інспекція анкера завершена штатно.")
      record.photos.attach(
        io: StringIO.new("fake-jpeg-bytes"), filename: "evidence.jpg", content_type: "image/jpeg"
      )

      records = described_class.call(user)[:maintenance_records]
      expect(records.size).to eq(1)
      expect(records.first[:photos].first).to include(filename: "evidence.jpg", content_type: "image/jpeg")
      expect(JSON.generate(records)).not_to include("fake-jpeg-bytes")
    end

    # Гілкові хвости nullable-полів: org відсутня (анонімізований сусід/безорговий
    # актор) · locked identity · performed_at=nil (колонка nullable БЕЗ NOT NULL —
    # рядок повз валідації можливий, тож `&.` живий, не декоративний).
    it "serializes a user without an organization and a locked identity" do
      orgless = create(:user, organization: nil)
      orgless.identities.create!(provider: "github", uid: "g-1", locked_at: Time.zone.local(2026, 8, 1, 12, 0))

      export = described_class.call(orgless)

      expect(export[:user][:organization_name]).to be_nil
      expect(export[:identities].first[:locked_at]).to eq(Time.zone.local(2026, 8, 1, 12, 0).iso8601)
    end

    it "serializes a maintenance record whose performed_at bypassed validations" do
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster)
      record = build(:maintenance_record, maintainable: tree, user: user,
                                          action_type: :inspection, performed_at: nil,
                                          notes: "Рядок повз валідації — nullable без backstop.")
      record.save!(validate: false)

      expect(described_class.call(user)[:maintenance_records].first[:performed_at]).to be_nil
    end

    it "does not leak another subject's data" do
      stranger = create(:user, organization: organization, email_address: "stranger@example.com")
      stranger.sessions.create!(ip_address: "192.0.2.99", user_agent: "OtherBrowser")

      json = JSON.generate(export)
      expect(json).not_to include("stranger@example.com")
      expect(json).not_to include("192.0.2.99")
    end
  end

  # 🔴 Дериваційний ліхтар (§Guard-craft #57-клас): нова PII-колонка `users`
  # мусить УПАСТИ тут, доки її не внесено або в експорт, або в оголошені
  # виключення — інакше DSAR тихо відстає від схеми. Той самий іменний патерн,
  # що в `pii_register_spec` (реєстр стереже ДОКУМЕНТАЦІЮ, цей гейт — ВІДДАЧУ).
  describe "schema parity" do
    # Метод, не константа: describe-блок не є неймспейсом (LeakyConstantDeclaration).
    def pii_pattern
      /email|phone|first_name|last_name|full_name|telegram|push_token|ip_address|
       user_agent|recovery_codes|passport|birth|national_id|passw/xi
    end

    # Креденшели — свідомо НЕ віддаються (докблок сервісу); кожен новий запис
    # тут вимагає тієї самої підстави.
    def declared_credentials = %w[password_digest recovery_codes]

    it "exports (or declares) every PII-named column of users" do
      pii_columns = User.column_names.grep(pii_pattern)
      expect(pii_columns).not_to be_empty # ліхтар популяції

      exported_keys = described_class.call(user)[:user].keys.map(&:to_s)
      unaccounted = pii_columns - exported_keys - declared_credentials
      expect(unaccounted).to be_empty,
        "PII-колонки users поза DSAR-експортом і поза оголошеними виключеннями: #{unaccounted.inspect}"
    end
  end
end
