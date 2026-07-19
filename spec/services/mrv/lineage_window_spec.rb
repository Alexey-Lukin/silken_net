# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mrv::LineageWindow do
  let(:tree) { create(:tree) }
  let(:wallet) { tree.wallet }

  def tx_with_window(from_at:, from_id:, to_at:, to_id:)
    build(:blockchain_transaction, wallet: wallet,
                                   telemetry_window_from_at: from_at, telemetry_window_from_id: from_id,
                                   telemetry_window_to_at: to_at, telemetry_window_to_id: to_id)
  end

  describe ".logs_for" do
    it "returns logs strictly inside (from..to] in canonical order" do
      l1 = create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
      l2 = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      l3 = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)

      tx = tx_with_window(from_at: l1.created_at, from_id: l1.id,
                          to_at: l2.created_at, to_id: l2.id)
      expect(described_class.logs_for(tx).map(&:id)).to eq([ l2.id ])
      expect(described_class.logs_for(tx).map(&:id)).not_to include(l1.id, l3.id)
    end

    it "id-tiebreak: два логи з ІДЕНТИЧНИМ created_at розводяться по вікнах tuple-порівнянням" do
      t = 2.hours.ago
      la = create(:telemetry_log, tree: tree, created_at: t)
      lb = create(:telemetry_log, tree: tree, created_at: t)
      first_id, second_id = [ la.id, lb.id ].sort

      tx = tx_with_window(from_at: t, from_id: first_id, to_at: t, to_id: second_id)
      expect(described_class.logs_for(tx).map(&:id)).to eq([ second_id ])
    end

    it "empty window (from == to) → нуль рядків" do
      log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = tx_with_window(from_at: log.created_at, from_id: log.id,
                          to_at: log.created_at, to_id: log.id)
      expect(described_class.logs_for(tx)).to be_empty
    end

    it "returns none for a wallet-less (cluster-sourced) tx or nil window_to" do
      orphan = build(:blockchain_transaction, wallet: nil,
                                              telemetry_window_to_at: 1.hour.ago, telemetry_window_to_id: 1)
      expect(described_class.logs_for(orphan)).to be_empty
      expect(described_class.logs_for(tx_with_window(from_at: nil, from_id: nil, to_at: nil, to_id: nil)))
        .to be_empty
    end

    it "несе «голі» created_at-межі поруч із tuple (partition-pruning — EXPLAIN-клас з ревю)" do
      log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = tx_with_window(from_at: 3.hours.ago, from_id: 1,
                          to_at: log.created_at, to_id: log.id)
      sql = described_class.logs_for(tx).to_sql
      expect(sql).to include("\"telemetry_logs\".\"created_at\" <=")
      expect(sql).to include("\"telemetry_logs\".\"created_at\" >=")
    end
  end

  describe ".root_for" do
    it "nil для порожнього вікна, корінь leaf-CID'ів для непорожнього" do
      log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = tx_with_window(from_at: nil, from_id: nil, to_at: log.created_at, to_id: log.id)
      expect(described_class.root_for(tx)).to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(log) ]))
      empty = tx_with_window(from_at: log.created_at, from_id: log.id,
                             to_at: log.created_at, to_id: log.id)
      expect(described_class.root_for(empty)).to be_nil
    end
  end
end
