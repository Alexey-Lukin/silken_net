# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemAudits::Index do
  # [TEST.12] Субʼєкт тут не AR-модель, а `Struct` рівно з пʼяти полів — тож
  # контракт ЖОРСТКІШИЙ: мок доти дописував `id` і `ok?`, яких на ньому немає
  # взагалі, і оголошував `critical` незалежно від `delta`, тоді як сервіс
  # виводить його порівнянням із порогом. Поріг береться з дому (константа
  # сервісу), а не переписується числом; сама формула деривації належить
  # `spec/services/chain_audit_service_spec.rb`, тут перевіряється рендер.
  def audit_with(delta:, checked_at: Time.parse("2024-01-15 12:00:00 UTC"))
    ChainAuditService::Result.new(
      db_total: 1000.0,
      chain_total: 1000.0 - delta,
      delta: delta,
      critical: delta > ChainAuditService::CRITICAL_DELTA_THRESHOLD,
      checked_at: checked_at
    )
  end

  let(:ok_audit)       { audit_with(delta: 0.0) }
  let(:critical_audit) { audit_with(delta: 1.5) }

  describe "header" do
    # [I18N.1-нейминг] Заголовок секції знято: сторінка має ОДНУ секцію, тож
    # її ім'я жило двічі й по-різному — «System Audit» у верхній панелі (h1 від
    # layout) і «⛓️ Chain Audit — System Integrity» тут. Пін інвертовано.
    it "does not duplicate the page name the layout already renders" do
      html = render_component(audit: ok_audit)
      expect(html).not_to include("Chain Audit")
    end

    it "renders the descriptive subtitle" do
      html = render_component(audit: ok_audit)
      expect(html).to include("Comparison of SCC sum")
    end
  end

  describe "status badge" do
    it "renders ok badge when audit is not critical" do
      html = render_component(audit: ok_audit)
      expect(html).to include("ok")
    end

    it "renders critical badge when audit is critical" do
      html = render_component(audit: critical_audit)
      expect(html).to include("critical")
    end
  end

  describe "status banner" do
    it "renders INTEGRITY OK banner for passing audit" do
      html = render_component(audit: ok_audit)
      expect(html).to include("INTEGRITY OK")
    end

    it "renders CRITICAL banner when delta exceeds threshold" do
      html = render_component(audit: critical_audit)
      expect(html).to include("CRITICAL")
    end
  end

  describe "comparison table" do
    it "renders Postgres DB row" do
      html = render_component(audit: ok_audit)
      expect(html).to include("Postgres DB")
    end

    it "renders Polygon Smart Contract row" do
      html = render_component(audit: ok_audit)
      expect(html).to include("Polygon Smart Contract")
    end

    it "renders Delta row" do
      html = render_component(audit: ok_audit)
      expect(html).to include("Delta")
    end

    it "renders db_total formatted as decimal" do
      html = render_component(audit: ok_audit)
      expect(html).to include("1000.000000")
    end

    it "renders chain_total value" do
      html = render_component(audit: critical_audit)
      expect(html).to include("998.500000")
    end

    it "renders delta value" do
      html = render_component(audit: critical_audit)
      expect(html).to include("1.500000")
    end

    it "highlights delta row red when critical" do
      html = render_component(audit: critical_audit)
      expect(html).to include("bg-status-danger/10")
    end

    it "highlights delta row emerald when ok" do
      html = render_component(audit: ok_audit)
      expect(html).to include("bg-gaia-surface-sunken")
    end
  end

  describe "timestamp footer" do
    it "renders checked at timestamp" do
      html = render_component(audit: ok_audit)
      expect(html).to include("Checked at")
      expect(html).to include("2024-01-15")
    end
  end
end
