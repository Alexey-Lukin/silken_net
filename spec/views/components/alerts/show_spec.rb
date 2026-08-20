# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.31] Сторінка тривоги: валідна table-обгортка навколо Row + SOP-панель.
RSpec.describe Alerts::Show do
  # Реальний незбережений запис [TEST.12]: message рендериться через
  # message_key-читач, тож фікстура подає ключ, а не прозу.
  let(:cluster) { Cluster.new(name: "Sector-7") }
  let(:alert) do
    EwsAlert.new(
      alert_type: :fire_detected, severity: :critical, status: :active,
      message_key: "chainsaw_detected", message_params: {}, cluster: cluster,
      created_at: Time.zone.local(2026, 8, 20, 12, 0, 0)
    )
  end
  let(:html) { render_component(alert: alert) }

  describe "rendering" do
    it "wraps the row in a real table (a bare <tr> outside <table> is dropped by the browser)" do
      expect(html).to include("<table")
      expect(html).to include("<tbody")
    end

    it "mirrors the index column headers" do
      expect(html).to include(I18n.t("alerts.table.severity"))
      expect(html).to include(I18n.t("alerts.table.command"))
    end

    it "renders the SOP heading" do
      expect(html).to include(I18n.t("alerts.show.sop.title"))
    end
  end

  describe "SOP steps" do
    it "renders all three operational steps in an ordered list" do
      expect(html).to include("<ol")
      described_class::SOP_STEPS.each do |step|
        expect(html).to include(I18n.t("alerts.show.sop.steps.#{step}.title"))
        expect(html).to include(I18n.t("alerts.show.sop.steps.#{step}.body"))
      end
    end

    # Порядок несе сенс (acknowledge → verify → field_audit) — ol, не ul,
    # і сама послідовність у константі, з якої рендер деривується.
    it "keeps the ratified operational order" do
      expect(described_class::SOP_STEPS).to eq(%i[acknowledge verify field_audit])
      positions = described_class::SOP_STEPS.map { |s| html.index(I18n.t("alerts.show.sop.steps.#{s}.title")) }
      expect(positions).to eq(positions.sort)
    end
  end

  describe "domain placeholder" do
    # Чесний порожній стан: називає ВІДСУТНІСТЬ партнерського джерела,
    # а не тимчасовість (клас ARCH.103 «порожнеча мусить мати голос»).
    it "honestly names the missing partner SOP content" do
      expect(html).to include(I18n.t("alerts.show.sop.domain.pending"))
    end

    it "does not invent domain tactics content beyond the placeholder" do
      section = html[html.index(I18n.t("alerts.show.sop.domain.title"))..]
      expect(section).to include(I18n.t("alerts.show.sop.domain.pending"))
    end
  end

  describe "accessibility" do
    it "labels the SOP region via aria-labelledby" do
      expect(html).to include('aria-labelledby="sop-heading"')
      expect(html).to include('id="sop-heading"')
    end

    it "renders the table with role=table and scoped headers" do
      expect(html).to include('role="table"')
      expect(html).to include('scope="col"')
    end
  end

  describe "design system compliance" do
    it "uses gaia tokens for the panel chrome" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
      expect(html).to include("text-gaia-text-muted")
    end
  end

  describe "resolve visibility (UI.5 fail-closed default)" do
    # Дефолт current_user: nil → Row ховає бойову кнопку: пін на ШЛЯХ дії,
    # бо саме він зникає з розмітки (текст кнопки локалізований і мінливий).
    it "does not render the resolve action without an actor" do
      expect(html).not_to include("/resolve")
    end
  end
end
