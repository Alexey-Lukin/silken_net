# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.31] Сторінка тривоги: валідна table-обгортка навколо Row + SOP-панель.
RSpec.describe Alerts::Show do
  # Реальний незбережений запис [TEST.12]: message рендериться через
  # message_key-читач, тож фікстура подає ключ, а не прозу.
  let(:cluster) { Cluster.new(name: "Sector-7") }
  # `id` присвоєно навмисно: CTA нижче несе його в query-рядку, а на записі без
  # id Rails мовчки викидає nil-параметр — пін став би зеленим на порожньому.
  let(:alert) { build_alert(id: 42) }
  let(:html) { render_component(alert: alert) }

  def build_alert(**overrides)
    EwsAlert.new({
      alert_type: :fire_detected, severity: :critical, status: :active,
      message_key: "chainsaw_detected", message_params: {}, cluster: cluster,
      created_at: Time.zone.local(2026, 8, 20, 12, 0, 0)
    }.merge(overrides))
  end


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

  # [E.20] Крок `field_audit` був ТУПИКОМ: `maintenance_records#new` уже читав
  # `ews_alert_id`, тобто механізм існував, а пускача не було. Пінимо не шлях, а
  # ЗАПИТ — посилання без `ews_alert_id` виглядає робочим і мовчки заводить запис
  # без зчеплення з тривогою, тобто рівно те, чого пункт і не мав.
  describe "field-audit CTA [E.20]" do
    let(:forester) { build_stubbed(:user, :forester) }

    def render_for(actor, subject_alert = alert)
      render_component(alert: subject_alert, current_user: actor)
    end

    it "carries the alert id into the maintenance form" do
      rendered = render_for(forester)

      expect(rendered).to include(I18n.t("alerts.show.sop.steps.field_audit.cta"))
      expect(rendered).to include("ews_alert_id=42")
    end

    it "prefills the maintainable when the alert names a tree" do
      rendered = render_for(forester, build_alert(id: 91, tree_id: 5))

      expect(rendered).to include("ews_alert_id=91")
      expect(rendered).to include("maintainable_id=5")
      expect(rendered).to include("maintainable_type=Tree")
    end

    # Cluster-level тривога (`tree_id` NULL — так пишуться blackout і staleness)
    # єдиного maintainable НЕ має; підставлений id завів би запис про не той об'єкт.
    it "does not fabricate a maintainable for a cluster-level alert" do
      rendered = render_for(forester)

      expect(rendered).to include("ews_alert_id=42")  # множина непорожня
      expect(rendered).not_to include("maintainable_id")
    end

    # [UI.6] Увесь MaintenanceRecordsController стоїть за `authorize_forester!`,
    # тож нижчій ролі посилання вело б у 403.
    it "hides the CTA from investor and fails closed without an actor" do
      [ build_stubbed(:user, :investor), nil ].each do |actor|
        rendered = render_for(actor)

        # Панель СЕБЕ відрендерила — інакше «немає посилання» було б вакуумним.
        expect(rendered).to include(I18n.t("alerts.show.sop.steps.field_audit.title"))
        expect(rendered).not_to include("/maintenance_records/new")
      end
    end
  end

  # [E.20] Панель «хто зараз на гачку». Пін на ШЛЯХ дії, а не на текст кнопки:
  # текст локалізований і мінливий, а зникає з розмітки саме шлях.
  describe "assignment panel [E.20]" do
    let(:forester) { build_stubbed(:user, :forester) }
    let(:colleague) { build_stubbed(:user, :forester) }
    let(:admin) { build_stubbed(:user, :admin) }

    def render_for(actor, subject_alert = alert)
      render_component(alert: subject_alert, current_user: actor)
    end

    it "names the empty state instead of showing a blank row" do
      rendered = render_for(forester)

      expect(rendered).to include(I18n.t("alerts.show.assignment.unassigned"))
      expect(rendered).to include("/alerts/42/claim")
    end

    it "shows the assignee and offers release to them" do
      rendered = render_for(forester, build_alert(id: 42, assignee: forester, assigned_at: Time.zone.local(2026, 8, 24, 9, 0, 0)))

      expect(rendered).to include(forester.full_name)
      expect(rendered).to include("/alerts/42/release")
      expect(rendered).not_to include("/alerts/42/claim")
    end

    # Право взяти ⊥ право відпустити: звичайний колега бачить, ХТО на гачку,
    # але кнопки не має — інакше вона обіцяла б 403.
    it "shows a colleague who holds it, without offering them any action" do
      rendered = render_for(colleague, build_alert(id: 42, assignee: forester, assigned_at: Time.zone.local(2026, 8, 24, 9, 0, 0)))

      expect(rendered).to include(forester.full_name)
      expect(rendered).not_to include("/alerts/42/release")
      expect(rendered).not_to include("/alerts/42/claim")
    end

    # Без цієї гілки один хибний клік замикав би тривогу на людині назавжди.
    it "lets an admin release someone else's alert" do
      rendered = render_for(admin, build_alert(id: 42, assignee: forester, assigned_at: Time.zone.local(2026, 8, 24, 9, 0, 0)))

      expect(rendered).to include("/alerts/42/release")
    end

    it "offers nothing on a resolved alert" do
      rendered = render_for(forester, build_alert(id: 42, status: :resolved))

      expect(rendered).to include(I18n.t("alerts.show.assignment.title"))  # панель відрендерилась
      expect(rendered).not_to include("/alerts/42/claim")
    end

    it "hides the actions from investor and fails closed without an actor" do
      [ build_stubbed(:user, :investor), nil ].each do |actor|
        rendered = render_for(actor)

        expect(rendered).to include(I18n.t("alerts.show.assignment.title"))
        expect(rendered).not_to include("/alerts/42/claim")
      end
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
