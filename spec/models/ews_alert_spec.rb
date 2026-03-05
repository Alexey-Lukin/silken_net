# frozen_string_literal: true

require "rails_helper"

RSpec.describe EwsAlert, type: :model do
  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to cluster" do
      association = described_class.reflect_on_association(:cluster)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_falsey
    end

    it "belongs to tree (optional)" do
      association = described_class.reflect_on_association(:tree)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to eq(true)
    end

    it "belongs to resolver (optional User)" do
      association = described_class.reflect_on_association(:resolver)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:class_name]).to eq("User")
      expect(association.options[:foreign_key]).to eq("resolved_by")
      expect(association.options[:optional]).to eq(true)
    end
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines status enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:status_active?)
      expect(alert).to respond_to(:status_resolved?)
      expect(alert).to respond_to(:status_ignored?)
    end

    it "defines severity enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:severity_low?)
      expect(alert).to respond_to(:severity_medium?)
      expect(alert).to respond_to(:severity_critical?)
    end

    it "defines alert_type enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:alert_type_severe_drought?)
      expect(alert).to respond_to(:alert_type_fire_detected?)
      expect(alert).to respond_to(:alert_type_system_fault?)
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    describe "presence" do
      it "requires severity" do
        alert = build(:ews_alert, severity: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:severity]).to be_present
      end

      it "requires alert_type" do
        alert = build(:ews_alert, alert_type: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:alert_type]).to be_present
      end

      it "requires message" do
        alert = build(:ews_alert, message: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:message]).to be_present
      end
    end

    describe "deduplication (Storm Protection)" do
      it "prevents duplicate active alerts for the same tree and alert_type" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)
        duplicate = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:alert_type]).to include("вже є активним для цього вузла")
      end

      it "allows same alert_type on different trees" do
        cluster = create(:cluster)
        tree_a = create(:tree, cluster: cluster)
        tree_b = create(:tree, cluster: cluster)

        create(:ews_alert, tree: tree_a, cluster: cluster, alert_type: :fire_detected, status: :active)
        second = build(:ews_alert, tree: tree_b, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(second).to be_valid
      end

      it "allows different alert_types on the same tree" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :severe_drought, status: :active)

        expect(second).to be_valid
      end

      it "allows duplicate alert_type if previous alert is resolved" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :resolved)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(second).to be_valid
      end

      it "skips uniqueness check when tree_id is nil (cluster-level alert)" do
        cluster = create(:cluster)

        create(:ews_alert, tree: nil, cluster: cluster, alert_type: :system_fault, status: :active)
        second = build(:ews_alert, tree: nil, cluster: cluster, alert_type: :system_fault, status: :active)

        expect(second).to be_valid
      end

      it "skips uniqueness check for non-active statuses" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :ignored)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :ignored)

        expect(second).to be_valid
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".unresolved" do
      it "returns only active alerts" do
        active = create(:ews_alert, status: :active)
        _resolved = create(:ews_alert, status: :resolved)
        _ignored = create(:ews_alert, status: :ignored)

        expect(described_class.unresolved).to eq([ active ])
      end
    end

    describe ".critical" do
      it "returns only critical active alerts" do
        critical_active = create(:ews_alert, :fire)
        _medium_active = create(:ews_alert, :drought)
        _critical_resolved = create(:ews_alert, severity: :critical, alert_type: :fire_detected, status: :resolved)

        expect(described_class.critical).to eq([ critical_active ])
      end
    end

    describe ".recent" do
      it "returns alerts ordered by created_at desc, limited to 20" do
        old_alert = create(:ews_alert, created_at: 2.days.ago)
        new_alert = create(:ews_alert, created_at: 1.minute.ago)

        results = described_class.recent
        expect(results.first).to eq(new_alert)
        expect(results.last).to eq(old_alert)
      end
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "callbacks" do
    describe "after_create_commit :dispatch_notifications!" do
      it "enqueues AlertNotificationWorker" do
        allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!).and_call_original
        expect(AlertNotificationWorker).to receive(:perform_async).with(kind_of(Integer))
        create(:ews_alert, :fire)
      end
    end
  end

  # =========================================================================
  # METHODS
  # =========================================================================
  describe "#resolve!" do
    it "sets status and resolved_at" do
      alert = create(:ews_alert, :drought)
      user = create(:user, :forester)

      alert.resolve!(user: user, notes: "Irrigation activated manually")
      alert.reload

      expect(alert).to be_status_resolved
      expect(alert.resolved_at).not_to be_nil
      expect(alert.resolver).to eq(user)
      expect(alert.resolution_notes).to eq("Irrigation activated manually")
    end

    it "uses default notes when not specified" do
      alert = create(:ews_alert, :drought)
      alert.resolve!
      alert.reload

      expect(alert.resolution_notes).to eq("Закрито системою")
    end

    it "returns true on success" do
      alert = create(:ews_alert, :drought)
      expect(alert.resolve!).to be true
    end

    it "clears the Redis silence filter" do
      alert = create(:ews_alert, :fire)
      silence_key = "ews_silence:#{alert.tree_id}:#{alert.alert_type}"
      Rails.cache.write(silence_key, true)

      alert.resolve!

      expect(Rails.cache.exist?(silence_key)).to be false
    end

    it "closes associated maintenance records" do
      alert = create(:ews_alert, :fire)

      expect(MaintenanceRecord).to receive(:where)
        .with(ews_alert_id: alert.id)
        .and_return(double(update_all: 0))

      alert.resolve!
    end
  end

  describe "#coordinates" do
    it "returns tree coordinates when tree is present" do
      alert = create(:ews_alert, :drought)
      coords = alert.coordinates

      expect(coords).to eq([ alert.tree.latitude, alert.tree.longitude ])
    end

    it "falls back to cluster geo_center when tree has no GPS" do
      cluster = create(:cluster)
      tree = create(:tree, cluster: cluster, latitude: nil, longitude: nil)
      alert = create(:ews_alert, tree: tree, cluster: cluster)

      geo_center = { lat: 50.0, lng: 30.0 }
      allow(cluster).to receive(:geo_center).and_return(geo_center)

      coords = alert.coordinates
      expect(coords).to eq([ 50.0, 30.0 ])
    end

    it "falls back to [0.0, 0.0] when no coordinates available" do
      cluster = create(:cluster)
      alert = create(:ews_alert, tree: nil, cluster: cluster)

      allow(cluster).to receive(:geo_center).and_return(nil)

      coords = alert.coordinates
      expect(coords).to eq([ 0.0, 0.0 ])
    end
  end

  describe "#actionable?" do
    it "returns true for critical fire" do
      alert = create(:ews_alert, :fire)
      expect(alert).to be_actionable
    end

    it "returns true for critical drought" do
      alert = create(:ews_alert, severity: :critical, alert_type: :severe_drought)
      expect(alert).to be_actionable
    end

    it "returns false for medium drought" do
      alert = create(:ews_alert, :drought)
      expect(alert).not_to be_actionable
    end

    it "returns false for critical vandalism" do
      alert = create(:ews_alert, severity: :critical, alert_type: :vandalism_breach)
      expect(alert).not_to be_actionable
    end

    it "returns false for low fire" do
      alert = create(:ews_alert, severity: :low, alert_type: :fire_detected)
      expect(alert).not_to be_actionable
    end
  end

  # =========================================================================
  # THROTTLING
  # =========================================================================
  describe "broadcast throttling" do
    it "defines BROADCAST_THROTTLE_SECONDS constant" do
      expect(described_class::BROADCAST_THROTTLE_SECONDS).to eq(5)
    end
  end

  # =========================================================================
  # PRIVATE METHODS
  # =========================================================================
  describe "#clear_silence_filter! (private)" do
    it "deletes the Redis silence key for tree+alert_type" do
      alert = create(:ews_alert, :fire)
      silence_key = "ews_silence:#{alert.tree_id}:#{alert.alert_type}"
      Rails.cache.write(silence_key, true)

      alert.send(:clear_silence_filter!)

      expect(Rails.cache.exist?(silence_key)).to be false
    end

    it "does nothing when tree_id is nil" do
      alert = create(:ews_alert, tree: nil)

      expect(Rails.cache).not_to receive(:delete)
      alert.send(:clear_silence_filter!)
    end
  end

  # =========================================================================
  # FACTORY TRAITS
  # =========================================================================
  describe "factory" do
    it "creates a valid default ews_alert" do
      expect(build(:ews_alert)).to be_valid
    end

    it "creates a valid drought alert" do
      alert = build(:ews_alert, :drought)
      expect(alert).to be_valid
      expect(alert).to be_severity_medium
      expect(alert).to be_alert_type_severe_drought
    end

    it "creates a valid fire alert" do
      alert = build(:ews_alert, :fire)
      expect(alert).to be_valid
      expect(alert).to be_severity_critical
      expect(alert).to be_alert_type_fire_detected
    end
  end
end
