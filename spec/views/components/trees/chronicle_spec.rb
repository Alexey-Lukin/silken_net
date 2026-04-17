# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Chronicle do
  def mock_pagy(count: 5, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      prev: nil, next: nil, vars: { items: 20 }
    )
    pg.define_singleton_method(:series) { [1] }
    pg
  end

  def mock_tree(id: 1, did: "SNET-00000042")
    t = OpenStruct.new(id: id, did: did)
    t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
    t.define_singleton_method(:to_key) { [id] }
    t.define_singleton_method(:to_param) { id.to_s }
    t
  end

  def mock_entry(title: "Telemetry Logged", description: "Normal pulse detected.",
                 event_type: :homeostasis, severity: :info,
                 icon: "🌱", date: 1.day.ago)
    OpenStruct.new(
      title: title,
      description: description,
      event_type: event_type,
      severity: severity,
      icon: icon,
      date: date
    )
  end

  def render_component(tree:, entries:, pagy:)
    ApplicationController.renderer.render(
      described_class.new(tree: tree, entries: entries, pagy: pagy),
      layout: false
    )
  end

  let(:tree) { mock_tree }
  let(:pagy) { mock_pagy(count: 2) }
  let(:entry) { mock_entry }
  let(:html) { render_component(tree: tree, entries: [entry], pagy: pagy) }

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
      expect(html).to include("🌱")
    end

    it "renders the event_type badge" do
      expect(html).to include("homeostasis")
    end

    it "renders the date in dd.mm format" do
      html_with_date = render_component(
        tree: tree,
        entries: [mock_entry(date: Time.zone.parse("2025-03-07 10:00:00"))],
        pagy: pagy
      )
      expect(html_with_date).to include("07.03")
    end
  end

  describe "event types" do
    it "renders alert events with danger styling" do
      alert_entry = mock_entry(event_type: :alert, severity: :critical, title: "FIRE DETECTED")
      html = render_component(tree: tree, entries: [alert_entry], pagy: pagy)
      expect(html).to include("FIRE DETECTED")
    end

    it "renders maintenance events" do
      maint_entry = mock_entry(event_type: :maintenance, title: "Sensor Replaced", icon: "🔧")
      html = render_component(tree: tree, entries: [maint_entry], pagy: pagy)
      expect(html).to include("Sensor Replaced")
    end

    it "renders minting events" do
      mint_entry = mock_entry(event_type: :minting, title: "SCC Minted", icon: "💎")
      html = render_component(tree: tree, entries: [mint_entry], pagy: pagy)
      expect(html).to include("SCC Minted")
    end
  end

  describe "empty state" do
    it "renders empty state message when entries are empty" do
      html = render_component(tree: tree, entries: [], pagy: mock_pagy(count: 0))
      expect(html).to include("No chronicle events recorded")
    end

    it "renders the empty state description" do
      html = render_component(tree: tree, entries: [], pagy: mock_pagy(count: 0))
      expect(html).to include("Events will appear here")
    end
  end

  describe "severity border classes" do
    it "renders critical severity with danger border" do
      critical_entry = mock_entry(severity: :critical, title: "Critical Event")
      html = render_component(tree: tree, entries: [critical_entry], pagy: pagy)
      expect(html).to include("border-status-danger-accent")
    end

    it "renders warning severity with warning border" do
      warning_entry = mock_entry(severity: :warning, title: "Warning Event")
      html = render_component(tree: tree, entries: [warning_entry], pagy: pagy)
      expect(html).to include("border-status-warning")
    end
  end
end
