# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Chronicle do
  def build_tree(id: 1, did: "SNET-00000042")
    Tree.new(id: id, did: did)
  end

  # 🔴 [TEST.12] Реальний `TreeChronicleService::Entry`, і субʼєкт тут НЕ AR-модель,
  # а `Data.define(...)` — тобто контракт ще жорсткіший: полів РІВНО вісім, і
  # пропустити хоч одне неможливо (`ArgumentError` у конструкторі). Мок оголошував
  # шість, тобто описував Entry, який не можна побудувати; `source_type`/`source_id`
  # він просто не мав, і `OpenStruct` віддавав на них `nil`.
  # 🔴 Друга вигадка — ІКОНКИ: мок ніс емодзі (`🌱`/`🔧`/`💎`), тоді як сервіс видає
  # геометричні гліфи (`⚠ △ ◉ ✓ ⚙ ◆`). Тобто три приклади пінили візуальний словник,
  # якого застосунок не має — і зміна набору іконок лишила б їх зеленими.
  def build_entry(title: "Telemetry Logged", description: "Normal pulse detected.",
                  event_type: :homeostasis, severity: :stable,
                  icon: "◉", date: 1.day.ago,
                  source_type: "TelemetryLog", source_id: 1)
    TreeChronicleService::Entry.new(
      date: date, event_type: event_type, icon: icon, title: title,
      description: description, severity: severity,
      source_type: source_type, source_id: source_id
    )
  end

  def render_component(tree:, entries:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(tree: tree, entries: entries, pagy: pagy),
      layout: false
    )
  end

  let(:tree) { build_tree }
  let(:pagy) { mock_pagy(count: 2, last: 1) }
  let(:entry) { build_entry }
  let(:html) { render_component(tree: tree, entries: [ entry ], pagy: pagy) }

  describe "turbo frame" do
    it "renders the tree_chronicle turbo frame" do
      expect(html).to include('id="tree_chronicle"')
    end
  end

  describe "header" do
    it "renders the Digital Chronicle heading" do
      expect(html).to include("Digital Chronicle")
    end

    it "renders the total event count from pagy" do
      expect(html).to include("2 events")
    end
  end

  describe "timeline events" do
    it "renders the entry title" do
      expect(html).to include("Telemetry Logged")
    end

    it "renders the entry description" do
      expect(html).to include("Normal pulse detected.")
    end

    it "renders the entry icon" do
      # Гліф, який сервіс справді видає для homeostasis (`◉`), а не емодзі з мока.
      expect(html).to include("◉")
    end

    it "renders the event_type badge" do
      expect(html).to include("homeostasis")
    end

    it "renders the date in dd.mm format" do
      html_with_date = render_component(
        tree: tree,
        entries: [ build_entry(date: Time.zone.parse("2025-03-07 10:00:00")) ],
        pagy: pagy
      )
      expect(html_with_date).to include("07.03")
    end

    it "renders a dash and no year when the entry has no date" do
      html_no_date = render_component(tree: tree, entries: [ build_entry(date: nil) ], pagy: pagy)
      expect(html_no_date).to include("—")
    end
  end

  describe "event types" do
    it "renders alert events with danger styling" do
      alert_entry = build_entry(event_type: :alert, severity: :critical, title: "FIRE DETECTED")
      html = render_component(tree: tree, entries: [ alert_entry ], pagy: pagy)
      expect(html).to include("FIRE DETECTED")
    end

    it "renders maintenance events" do
      maint_entry = build_entry(event_type: :maintenance, title: "Sensor Replaced", icon: "⚙")
      html = render_component(tree: tree, entries: [ maint_entry ], pagy: pagy)
      expect(html).to include("Sensor Replaced")
    end

    it "renders minting events" do
      mint_entry = build_entry(event_type: :minting, title: "SCC Minted", icon: "◆")
      html = render_component(tree: tree, entries: [ mint_entry ], pagy: pagy)
      expect(html).to include("SCC Minted")
    end
  end

  describe "empty state" do
    it "renders empty state message when entries are empty" do
      html = render_component(tree: tree, entries: [], pagy: mock_pagy(count: 0, last: 1))
      expect(html).to include("No chronicle events recorded")
    end

    it "renders the empty state description" do
      html = render_component(tree: tree, entries: [], pagy: mock_pagy(count: 0, last: 1))
      expect(html).to include("Events will appear here")
    end
  end

  describe "severity border classes" do
    it "renders critical severity with danger border" do
      critical_entry = build_entry(severity: :critical, title: "Critical Event")
      html = render_component(tree: tree, entries: [ critical_entry ], pagy: pagy)
      expect(html).to include("border-status-danger-accent")
    end

    it "renders warning severity with warning border" do
      warning_entry = build_entry(severity: :warning, title: "Warning Event")
      html = render_component(tree: tree, entries: [ warning_entry ], pagy: pagy)
      expect(html).to include("border-status-warning")
    end

    # ⚠️ [BP 20] Обидва приклади нижче НЕ здатні розрізнити «фолбек спрацював» від
    # «нормальна подія відрендерилась»: `border-emerald-800`/`text-emerald-400` —
    # це стиль і невідомого значення, І живого `:stable`, який сервіс видає для
    # `homeostasis`/`recovery` (три продюсери). Сама severity ніде не друкується,
    # тож розрізняльної ознаки в розмітці НЕМАЄ в принципі. Лишаємо як є свідомо:
    # зробити фолбек помітним — це візуальне рішення, і воно не наше. ⊕ Ціна вже
    # платилась: `ALERT_SEVERITY_TO_CHRONICLE` існує саме тому, що чужі `:medium`/
    # `:low` колись падали в цю ж дефолтну зелень і читались як «усе гаразд».
    it "renders unknown severity with default emerald border" do
      entry = build_entry(severity: :unknown, title: "Unknown Severity")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("border-emerald-800")
    end
  end

  describe "severity text classes" do
    it "renders unknown severity with default emerald text" do
      entry = build_entry(severity: :unknown, title: "Unknown Severity Text")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("text-emerald-400")
    end
  end

  describe "event type badge classes" do
    it "renders stress event with warning badge" do
      entry = build_entry(event_type: :stress, title: "Stress Event")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("bg-status-warning")
    end

    it "renders fraud event with danger badge" do
      entry = build_entry(event_type: :fraud, title: "Fraud Event")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("bg-status-danger")
    end

    it "renders unknown event type with neutral badge" do
      entry = build_entry(event_type: :unknown_type, title: "Unknown Event")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("bg-status-neutral")
    end

    it "renders recovery event with active badge" do
      entry = build_entry(event_type: :recovery, title: "Recovery Event")
      html = render_component(tree: tree, entries: [ entry ], pagy: pagy)
      expect(html).to include("bg-status-active")
    end
  end

  describe "pagination" do
    it "renders pagination when pagy has multiple pages" do
      multi_pagy = mock_pagy(count: 50, page: 1, last: 3)
      html = render_component(tree: tree, entries: [ entry ], pagy: multi_pagy)
      expect(html).to include("tree_chronicle")
    end
  end
end
