# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResetActuatorStateWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster) }
  let(:actuator) { create(:actuator, gateway: gateway, state: :active) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when actuator is active" do
      let(:command) do
        allow_any_instance_of(ActuatorCommand).to receive(:dispatch_to_edge!)
        cmd = create(:actuator_command, actuator: actuator, status: :acknowledged, sent_at: 1.minute.ago)
        cmd.update_column(:status, :acknowledged)
        cmd
      end

      it "resets actuator to idle state" do
        described_class.new.perform(command.id)

        actuator.reload
        expect(actuator.state).to eq("idle")
      end

      it "marks command as confirmed with completed_at" do
        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("confirmed")
        expect(command.completed_at).to be_present
      end

      it "broadcasts final state via Turbo" do
        described_class.new.perform(command.id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:twice)
      end
    end

    context "when actuator is not active" do
      let(:command) do
        allow_any_instance_of(ActuatorCommand).to receive(:dispatch_to_edge!)
        cmd = create(:actuator_command, actuator: actuator, status: :acknowledged)
        cmd.update_column(:status, :acknowledged)
        cmd
      end

      it "does not reset actuator but confirms acknowledged command" do
        actuator.update_column(:state, :maintenance_needed)

        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("confirmed")
        expect(actuator.reload.state).to eq("maintenance_needed")
      end

      it "skips confirmation if command is not acknowledged" do
        actuator.update_column(:state, :idle)
        command.update_column(:status, :failed)

        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("failed")
      end
    end

    it "returns early when command not found" do
      expect(Rails.logger).to receive(:warn).with(/не знайдено/)

      described_class.new.perform(-1)
    end

    context "when gateway has no cluster (nil organization chain)" do
      it "broadcasts without error when organization is nil" do
        allow_any_instance_of(ActuatorCommand).to receive(:dispatch_to_edge!)
        cmd = create(:actuator_command, actuator: actuator, status: :acknowledged, sent_at: 1.minute.ago)
        cmd.update_column(:status, :acknowledged)

        # Simulate nil in the gateway -> cluster -> organization chain
        allow(actuator).to receive(:gateway).and_return(nil)

        expect {
          described_class.new.perform(cmd.id)
        }.not_to raise_error

        actuator.reload
        expect(actuator.state).to eq("idle")
      end
    end
  end

  describe "gateway/cluster/organization nil chain" do
    it "handles gateway with cluster that has no organization" do
      # Verifies graceful handling when the safe navigation chain (gateway&.cluster&.organization) returns nil
      org_for_test = create(:organization)
      cluster_for_test = create(:cluster, organization: org_for_test)
      gateway_with_cluster = create(:gateway, cluster: cluster_for_test)
      actuator = create(:actuator, gateway: gateway_with_cluster, state: :active)
      command = create(:actuator_command, actuator: actuator, status: :issued)

      # Stub the chain to return nil at organization level
      allow_any_instance_of(Gateway).to receive(:cluster).and_return(
        double("cluster", organization_id: nil, organization: nil)
      )

      expect {
        described_class.new.perform(command.id)
      }.not_to raise_error
    end
  end
end
