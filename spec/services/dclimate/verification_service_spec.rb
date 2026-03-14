# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dclimate::VerificationService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:organization) { cluster.organization }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_new_alert)
    allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
    allow(InsurancePayoutWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_async)
  end

  describe "#perform" do
    context "when satellite confirms fire (fire_confirmed)" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      before do
        allow(service).to receive(:query_dclimate_api).and_return(:fire_confirmed)
      end

      it "updates satellite_status to verified" do
        service.perform
        alert.reload
        expect(alert).to be_satellite_verified
      end

      it "sets dclimate_ref" do
        service.perform
        alert.reload
        expect(alert.dclimate_ref).to start_with("dclimate:")
      end

      it "triggers InsurancePayoutWorker for triggered insurances" do
        insurance = create(:parametric_insurance, :triggered, cluster: cluster, organization: organization)
        service.perform
        expect(InsurancePayoutWorker).to have_received(:perform_async).with(insurance.id)
      end

      it "does not trigger payout when no triggered insurances exist" do
        service.perform
        expect(InsurancePayoutWorker).not_to have_received(:perform_async)
      end
    end

    context "when satellite sees clear sky (clear_sky_no_fire)" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      before do
        allow(service).to receive(:query_dclimate_api).and_return(:clear_sky_no_fire)
      end

      it "updates satellite_status to rejected_fraud" do
        service.perform
        alert.reload
        expect(alert).to be_satellite_rejected_fraud
      end

      it "sets dclimate_ref" do
        service.perform
        alert.reload
        expect(alert.dclimate_ref).to start_with("dclimate:")
      end

      it "triggers BurnCarbonTokensWorker for active NaaS contracts" do
        contract = create(:naas_contract, cluster: cluster, organization: organization)
        service.perform
        expect(BurnCarbonTokensWorker).to have_received(:perform_async)
          .with(organization.id, contract.id, tree.id)
      end
    end

    context "when satellite is obscured by clouds (obscured_by_clouds)" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      before do
        allow(service).to receive(:query_dclimate_api).and_return(:obscured_by_clouds)
      end

      it "raises Dclimate::OrbitalLagError" do
        expect { service.perform }.to raise_error(
          Dclimate::OrbitalLagError, /Satellite pass obscured/
        )
      end

      it "does not change satellite_status" do
        expect { service.perform }.to raise_error(Dclimate::OrbitalLagError)
        alert.reload
        expect(alert).to be_satellite_unverified
      end
    end

    context "when alert has no cluster" do
      let(:alert) { create(:ews_alert, :fire, cluster: nil, tree: nil) }

      it "does not raise error on fire_confirmed without cluster" do
        service = described_class.new(alert)
        allow(service).to receive(:query_dclimate_api).and_return(:fire_confirmed)
        expect { service.perform }.not_to raise_error
      end
    end
  end
end
