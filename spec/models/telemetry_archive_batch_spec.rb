# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [E.60 Фаза 1б] Реєстр mint-anchored архів-батчів: CAS-термінали (прецедент
# EthereumAnchor), NULL-root build_failed поза unique, repair-шлях.
RSpec.describe TelemetryArchiveBatch, type: :model do
  let(:root) { "a" * 64 }

  describe "validations" do
    it "accepts a 64-hex archive_root" do
      expect(described_class.new(archive_root: root, token_type: :carbon_coin)).to be_valid
    end

    it "rejects a non-hex archive_root" do
      batch = described_class.new(archive_root: "Z" * 64, token_type: :carbon_coin)
      expect(batch).not_to be_valid
    end

    it "requires archive_root unless build_failed" do
      expect(described_class.new(token_type: :carbon_coin)).not_to be_valid
      expect(described_class.new(token_type: :carbon_coin, status: :build_failed)).to be_valid
    end
  end

  describe "unique index (archive_root, token_type) WHERE archive_root IS NOT NULL" do
    it "deduplicates via create_or_find_by for the same root+token" do
      first = described_class.create!(archive_root: root, token_type: :carbon_coin)
      dup = described_class.create_or_find_by(archive_root: root, token_type: :carbon_coin)
      expect(dup.id).to eq(first.id)
    end

    it "keeps the same root for different token types as SEPARATE rows" do
      described_class.create!(archive_root: root, token_type: :carbon_coin)
      expect {
        described_class.create!(archive_root: root, token_type: :forest_coin)
      }.to change(described_class, :count).by(1)
    end

    it "does not collide multiple NULL-root build_failed rows (у т.ч. крос-токен)" do
      2.times { described_class.create!(token_type: :carbon_coin, status: :build_failed) }
      described_class.create!(token_type: :forest_coin, status: :build_failed)
      expect(described_class.status_build_failed.count).to eq(3)
    end
  end

  describe "CAS-гардовані термінали" do
    let(:batch) { described_class.create!(archive_root: root, token_type: :carbon_coin) }

    it "pins from pending exactly once" do
      expect(batch.mark_pinned!("bafkrei_x")).to be true
      expect(batch.reload).to be_status_pinned
      expect(batch.ipfs_cid).to eq("bafkrei_x")
    end

    it "does not let a stale copy overwrite a terminal (mismatch stays)" do
      batch.mark_mismatch!("rebuild root diverged")
      expect(batch.mark_pinned!("bafkrei_late")).to be false
      expect(batch.reload).to be_status_mismatch
    end

    it "does not re-escalate a pinned batch" do
      batch.mark_pinned!("bafkrei_x")
      expect(batch.mark_mismatch!("late")).to be false
      expect(batch.reload).to be_status_pinned
    end

    it "marks retention_expired and superseded only from pending" do
      batch.mark_superseded!
      expect(batch.reload).to be_status_superseded
      expect(batch.mark_retention_expired!("gone")).to be false
    end
  end

  describe "#repair!" do
    it "repairs build_failed → pending with a root" do
      failed = described_class.create!(token_type: :carbon_coin, status: :build_failed,
                                       error_message: "boom", tx_ids: [ 1, 2 ])
      expect(failed.repair!(root, leaf_count: 5, tx_count: 2)).to be true
      failed.reload
      expect(failed).to be_status_pending
      expect(failed.archive_root).to eq(root)
      expect(failed.error_message).to be_nil
    end

    it "refuses to repair a pending batch" do
      batch = described_class.create!(archive_root: root, token_type: :carbon_coin)
      expect(batch.repair!("b" * 64, leaf_count: 1, tx_count: 1)).to be false
    end

    it "abandon_repair! відмовляє не-build_failed станам" do
      batch = described_class.create!(archive_root: root, token_type: :carbon_coin)
      expect(batch.abandon_repair!("no-op")).to be false
      expect(batch.reload).to be_status_pending
    end
  end

  describe ".reconcilable" do
    it "includes stale pending/build_failed, excludes fresh and terminal" do
      stale_pending = described_class.create!(archive_root: root, token_type: :carbon_coin)
      stale_failed = described_class.create!(token_type: :carbon_coin, status: :build_failed)
      [ stale_pending, stale_failed ].each { |b| b.update_column(:updated_at, 3.hours.ago) }

      fresh = described_class.create!(archive_root: "b" * 64, token_type: :carbon_coin)
      pinned = described_class.create!(archive_root: "c" * 64, token_type: :carbon_coin)
      pinned.mark_pinned!("bafkrei_x")
      pinned.update_column(:updated_at, 3.hours.ago)

      expect(described_class.reconcilable).to contain_exactly(stale_pending, stale_failed)
      expect(described_class.reconcilable).not_to include(fresh, pinned)
    end
  end
end
