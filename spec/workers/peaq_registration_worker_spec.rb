# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeaqRegistrationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#perform" do
    it "calls Peaq::DidRegistryService and updates tree's peaq_did" do
      peaq_did = "did:peaq:0x#{"a" * 40}"
      service = instance_double(Peaq::DidRegistryService)
      allow(Peaq::DidRegistryService).to receive(:new).with(tree).and_return(service)
      allow(service).to receive(:register!).and_return(peaq_did)

      described_class.new.perform(tree.id)

      tree.reload
      expect(tree.peaq_did).to eq(peaq_did)
    end

    it "skips registration when tree already has peaq_did" do
      existing_did = "did:peaq:0x#{"b" * 40}"
      tree.update_column(:peaq_did, existing_did)

      expect(Peaq::DidRegistryService).not_to receive(:new)

      described_class.new.perform(tree.id)

      tree.reload
      expect(tree.peaq_did).to eq(existing_did)
    end

    it "returns early when tree is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)
      expect(Peaq::DidRegistryService).not_to receive(:new)

      described_class.new.perform(-1)
    end

    it "re-raises RegistrationError for Sidekiq retry" do
      service = instance_double(Peaq::DidRegistryService)
      allow(Peaq::DidRegistryService).to receive(:new).with(tree).and_return(service)
      allow(service).to receive(:register!).and_raise(
        Peaq::DidRegistryService::RegistrationError, "peaq node timeout"
      )

      expect {
        described_class.new.perform(tree.id)
      }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq node timeout/)

      tree.reload
      expect(tree.peaq_did).to be_nil
    end

    it "uses web3 queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 5" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(5)
    end

    context "when peaq_did is set by another process between service call and lock" do
      it "skips update when tree already has peaq_did under lock" do
        service = instance_double(Peaq::DidRegistryService)
        allow(Peaq::DidRegistryService).to receive(:new).and_return(service)
        allow(service).to receive(:register!).and_return("did:peaq:0x#{"c" * 40}")

        # Simulate: another process sets peaq_did after register! but before with_lock body
        original_with_lock = Tree.instance_method(:with_lock)
        allow_any_instance_of(Tree).to receive(:with_lock) do |tree_instance, &block|
          tree_instance.update_column(:peaq_did, "did:peaq:0x#{"d" * 40}")
          original_with_lock.bind_call(tree_instance, &block)
        end

        described_class.new.perform(tree.id)

        tree.reload
        # The concurrent write wins — the worker guard returns early inside the lock
        expect(tree.peaq_did).to eq("did:peaq:0x#{"d" * 40}")
      end
    end
  end
end
