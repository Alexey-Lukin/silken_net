# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tree, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "after_create callbacks" do
    it "creates a wallet after creation" do
      tree = create(:tree)

      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
    end
  end

  describe "DID normalization" do
    it "normalizes DID to uppercase" do
      tree = build(:tree, did: "snet-lowercase1")
      tree.valid?

      expect(tree.did).to eq("SNET-LOWERCASE1")
    end
  end

  describe "#mark_seen!" do
    it "updates last_seen_at" do
      tree = create(:tree)
      expect(tree.last_seen_at).to be_nil

      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).not_to be_nil
      expect(tree.last_seen_at).to be_within(2.seconds).of(Time.current)
    end
  end
end
