# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertNotificationWorker, type: :worker do
  let(:organization) { create(:organization, billing_email: "billing@forest.org") }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, latitude: 49.42, longitude: 32.06) }
  let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "broadcasts alert to cluster and organization ActionCable channels" do
      described_class.new.perform(alert.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("cluster_#{cluster.id}_alerts", hash_including(id: alert.id, severity: "critical"))
      expect(ActionCable.server).to have_received(:broadcast)
        .with("org_#{organization.id}_alerts", hash_including(id: alert.id, severity: "critical"))
    end

    it "uses tree coordinates when tree is present" do
      described_class.new.perform(alert.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("cluster_#{cluster.id}_alerts", hash_including(lat: tree.latitude, lng: tree.longitude))
    end

    it "enqueues SingleNotificationWorker for each admin/forester" do
      admin = create(:user, :admin, organization: organization)
      forester = create(:user, :forester, organization: organization)
      _investor = create(:user, :investor, organization: organization)

      described_class.new.perform(alert.id)

      # Critical alert: SMS + Push for admin and forester (4 jobs), no jobs for investor
      sms_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "sms" }
      push_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "push" }

      expect(sms_jobs.size).to eq(2)
      expect(push_jobs.size).to eq(2)
    end

    it "sends email for critical alerts with billing email" do
      mailer_double = double(deliver_later: true)
      notification_double = double(critical_notification: mailer_double)
      allow(AlertMailer).to receive(:with).and_return(notification_double)

      described_class.new.perform(alert.id)

      expect(AlertMailer).to have_received(:with).with(alert: alert)
    end

    it "does not send email for non-critical alerts" do
      medium_alert = create(:ews_alert, :drought, cluster: cluster, tree: tree)
      allow(AlertMailer).to receive(:with)

      described_class.new.perform(medium_alert.id)

      expect(AlertMailer).not_to have_received(:with)
    end

    it "falls back to cluster geo_center when tree has no coordinates" do
      no_tree_alert = create(:ews_alert, :fire, cluster: cluster, tree: nil)
      allow_any_instance_of(Cluster).to receive(:geo_center).and_return({ lat: 50.0, lng: 30.0 })

      described_class.new.perform(no_tree_alert.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("cluster_#{cluster.id}_alerts", hash_including(lat: 50.0, lng: 30.0))
    end

    it "falls back to first gateway when cluster has no geo_center" do
      gw = create(:gateway, cluster: cluster, latitude: 48.5, longitude: 31.5)
      no_tree_alert = create(:ews_alert, :fire, cluster: cluster, tree: nil)
      allow_any_instance_of(Cluster).to receive(:geo_center).and_return(nil)

      described_class.new.perform(no_tree_alert.id)

      expect(ActionCable.server).to have_received(:broadcast).at_least(:once)
    end

    it "sends nil coordinates when no location sources available" do
      empty_cluster = create(:cluster, organization: organization)
      no_loc_alert = create(:ews_alert, :fire, cluster: empty_cluster, tree: nil)
      allow_any_instance_of(Cluster).to receive(:geo_center).and_return(nil)

      described_class.new.perform(no_loc_alert.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("cluster_#{empty_cluster.id}_alerts", hash_including(lat: nil, lng: nil))
    end

    it "returns nil when alert not found" do
      expect(described_class.new.perform(-1)).to be_nil
    end

    it "handles ActionCable broadcast errors gracefully" do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "WebSocket error")

      # Should not raise — error is logged internally
      expect { described_class.new.perform(alert.id) }.not_to raise_error
    end
  end
end
