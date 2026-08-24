# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::TreeResolver do
  # golden g1 (заморожено обабіч — did_derivation_spec ↔ test_did_derive.c)
  let(:uid) { "0039002F3138511538323634" }
  let(:did) { "SNET-80B12004" }
  let(:cluster) { create(:cluster) }
  let(:family)  { create(:tree_family) }

  describe ".resolve! — чотири долі кремнію" do
    it "створює дерево з деривованим DID + кремнієвим паспортом" do
      tree = described_class.resolve!(uid_hex: uid, cluster_id: cluster.id, tree_family_id: family.id)

      expect(tree.did).to eq(did)
      expect(tree.silicon_uid_hex).to eq(uid)
      expect(tree.cluster_id).to eq(cluster.id)
      expect(tree.tree_family_id).to eq(family.id)
    end

    it "відмовляє create без cluster/family (K_ota + NOT NULL передумови)" do
      expect { described_class.resolve!(uid_hex: uid) }
        .to raise_error(described_class::MissingAttributesError, /CLUSTER_ID/)
      expect(Tree.find_by(did: did)).to be_nil
    end

    it "відмовляє create і коли бракує лише family (cluster даний)" do
      expect { described_class.resolve!(uid_hex: uid, cluster_id: cluster.id) }
        .to raise_error(described_class::MissingAttributesError, /TREE_FAMILY_ID/)
    end

    it "всиновлює чип legacy-деревом без паспорта (bind)" do
      legacy = create(:tree, did: did, silicon_uid_hex: nil)

      expect(described_class.resolve!(uid_hex: uid)).to eq(legacy)
      expect(legacy.reload.silicon_uid_hex).to eq(uid)
    end

    it "re-flash того самого чипа — ідемпотентний no-op" do
      tree = create(:tree, did: did, silicon_uid_hex: uid)

      expect(described_class.resolve!(uid_hex: uid)).to eq(tree)
      expect(tree.reload.silicon_uid_hex).to eq(uid)
    end

    it "чужий чип під тим самим DID → CollisionError (quarantine, без записів)" do
      create(:tree, did: did, silicon_uid_hex: "AAAAAAAABBBBBBBBCCCCCCCC")

      expect { described_class.resolve!(uid_hex: uid) }
        .to raise_error(described_class::CollisionError, /quarantine/)
      expect(Tree.find_by(did: did).silicon_uid_hex).to eq("AAAAAAAABBBBBBBBCCCCCCCC")
    end

    it "нормалізує вхідний uid (регістр/краї) перед усіма долями" do
      tree = described_class.resolve!(uid_hex: " 0039002f3138511538323634\n",
                                      cluster_id: cluster.id, tree_family_id: family.id)
      expect(tree.silicon_uid_hex).to eq(uid)
    end

    it "не enqueue'ить peaq-реєстрацію (offline-фабрика, transitional)" do
      allow(PeaqRegistrationWorker).to receive(:perform_async)
      described_class.resolve!(uid_hex: uid, cluster_id: cluster.id, tree_family_id: family.id)
      expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
    end
  end
end
