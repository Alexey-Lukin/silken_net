# frozen_string_literal: true

require "rails_helper"

RSpec.describe EcosystemHealingWorker, type: :worker do
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
  end

  describe "#perform" do
    context "when target is an Actuator with repair" do
      it "marks actuator as idle after repair" do
        actuator = create(:actuator, state: :maintenance_needed)
        record = build(:maintenance_record, :repair, maintainable: actuator)
        record.photos.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
        record.save!

        described_class.new.perform(record.id)

        actuator.reload
        expect(actuator.state).to eq("idle")
      end
    end

    context "when target is a Tree with decommissioning" do
      it "sets tree status to removed" do
        tree = create(:tree, status: :active)
        record = create(:maintenance_record, maintainable: tree, action_type: :decommissioning)

        described_class.new.perform(record.id)

        tree.reload
        expect(tree.status).to eq("removed")
      end
    end

    context "when target responds to mark_seen!" do
      it "calls mark_seen! on the target" do
        tree = create(:tree, status: :active)
        record = create(:maintenance_record, maintainable: tree, action_type: :inspection)

        expect_any_instance_of(Tree).to receive(:mark_seen!)

        described_class.new.perform(record.id)
      end
    end

    context "when associated EWS alert is active" do
      it "resolves the alert" do
        tree = create(:tree)
        alert = create(:ews_alert, cluster: tree.cluster, tree: tree, status: :active)
        record = build(:maintenance_record, :repair, maintainable: tree, ews_alert: alert)
        record.photos.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
        record.save!

        described_class.new.perform(record.id)

        alert.reload
        expect(alert.status).to eq("resolved")
        expect(alert.resolution_notes).to include("Відновлено")
      end
    end

    context "when alert is already resolved" do
      it "does not re-resolve" do
        tree = create(:tree)
        alert = create(:ews_alert, cluster: tree.cluster, tree: tree, status: :resolved,
                                   resolved_at: 1.hour.ago, resolution_notes: "Already done")
        record = create(:maintenance_record, maintainable: tree, ews_alert: alert)

        described_class.new.perform(record.id)

        alert.reload
        expect(alert.resolution_notes).to eq("Already done")
      end
    end

    it "raises RecordNotFound for missing record" do
      expect { described_class.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when target is a Gateway" do
      it "calls mark_seen! on the gateway and completes without error" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :inspection)

        expect_any_instance_of(Gateway).to receive(:mark_seen!)

        expect { described_class.new.perform(record.id) }.not_to raise_error
      end
    end
  end
end
