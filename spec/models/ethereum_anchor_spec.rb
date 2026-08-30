# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchor, type: :model do
  subject(:anchor) do
    described_class.new(
      state_root: "a" * 64,
      total_growth_points: 1000.0,
      chain_hash: "abc123",
      anchored_at: Time.current
    )
  end

  describe "validations" do
    it "is valid with correct attributes" do
      expect(anchor).to be_valid
    end

    it "requires state_root" do
      anchor.state_root = nil
      expect(anchor).not_to be_valid
      expect(anchor.errors[:state_root]).to include("can't be blank")
    end

    it "requires state_root to be 64-char hex" do
      anchor.state_root = "invalid"
      expect(anchor).not_to be_valid
      expect(anchor.errors[:state_root]).to include("must be a 64-char hex SHA-256")
    end

    it "requires total_growth_points" do
      anchor.total_growth_points = nil
      expect(anchor).not_to be_valid
    end

    it "requires chain_hash" do
      anchor.chain_hash = nil
      expect(anchor).not_to be_valid
    end

    it "requires anchored_at" do
      anchor.anchored_at = nil
      expect(anchor).not_to be_valid
    end

    it "validates state_root uniqueness" do
      anchor.save!
      duplicate = described_class.new(
        state_root: anchor.state_root,
        total_growth_points: 2000.0,
        chain_hash: "def456",
        anchored_at: Time.current
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:state_root]).to include("has already been taken")
    end

    it "validates tx_hash format when present" do
      anchor.tx_hash = "invalid_hash"
      expect(anchor).not_to be_valid
      expect(anchor.errors[:tx_hash]).to include("must be a valid Ethereum tx hash")
    end

    it "accepts valid tx_hash format" do
      anchor.tx_hash = "0x#{"ab" * 32}"
      expect(anchor).to be_valid
    end

    it "requires tx_hash for sent status" do
      anchor.status = :sent
      anchor.tx_hash = nil
      expect(anchor).not_to be_valid
      expect(anchor.errors[:tx_hash]).to include("can't be blank")
    end

    it "requires tx_hash for confirmed status" do
      anchor.status = :confirmed
      anchor.tx_hash = nil
      expect(anchor).not_to be_valid
    end

    it "validates block_number is positive integer" do
      anchor.block_number = -1
      expect(anchor).not_to be_valid
    end

    it "validates gas_used is non-negative" do
      anchor.gas_used = -1
      expect(anchor).not_to be_valid
    end

    it "validates nonce is a non-negative integer, allowing nil" do
      anchor.nonce = -1
      expect(anchor).not_to be_valid
      anchor.nonce = nil
      expect(anchor).to be_valid
    end
  end

  describe "enum :status" do
    it "defaults to pending" do
      expect(described_class.new.status).to eq("pending")
    end

    it "supports all statuses" do
      expect(described_class.statuses).to include(
        "pending" => 0, "sent" => 1, "confirmed" => 2, "failed" => 3, "manual_review" => 4
      )
    end
  end

  describe "#verify_state_root" do
    it "returns true when state_root matches recomputed hash" do
      freeze_time do
        now = Time.current.utc
        # [ARCH.97] Payload виписаний РУКОПИСНО й навмисно — це незалежне твердження
        # про контракт, а не переграш `aggregate_payload`; інакше пін не міг би впасти
        # від зміни формули. Дві грошові величини свідомо РІЗНІ: збіг чисел зробив би
        # пін сліпим до того, яка з них куди пішла.
        total_growth_points = BigDecimal("1000.5")
        total_scc_supply = BigDecimal("7.25")
        total_sfc = BigDecimal("0")
        active_tree_count = 0
        chain_hash = "test_chain_hash"
        expected_payload = "#{total_growth_points}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|" \
                           "#{now.iso8601}|#{total_scc_supply}"
        expected_root = Digest::SHA256.hexdigest(expected_payload)

        record = described_class.new(
          state_root: expected_root,
          total_growth_points: total_growth_points,
          total_scc_supply: total_scc_supply,
          chain_hash: chain_hash,
          anchored_at: now
        )

        expect(record.verify_state_root).to be true
      end
    end

    # [ARCH.97] Регресійний носій ПРОТИ мовчазного повернення шкали.
    #
    # Доказові величини приходять із `numeric(24,6)`-джерел (`wallets.balance`,
    # `blockchain_transactions.amount`), а колонки якоря були `numeric(30,4)`.
    # Generate хешує НЕокруглене значення в leaf0, verify перераховує зі ЗБЕРЕЖЕНОЇ
    # колонки — тож при 6-знаковому джерелі якір не сходився САМ ІЗ СОБОЮ, і
    # «зовнішній аудитор відтворить хеш» було хибним арифметично, а не концептуально.
    # Виміряно до фіксу: 1000.123456 → 1000.1235 → verify_state_root == false.
    # Приклад падає, щойно шкалу БУДЬ-ЯКОЇ доказової колонки опустять нижче за джерело.
    #
    # 🔴 Перша редакція цього піна подавала `total_sfc: 0` — і саме тому не побачила,
    # що третє поле лишилось на `numeric(30,4)` ще пів дня після «фіксу»: на нулі
    # розходження шкал НЕ ВИРАЗИМЕ за жодної шкали. Тож кожне decimal-поле payload'а
    # мусить нести тут ВЛАСНЕ 6-значне значення, інакше приклад доводить менше, ніж
    # твердить його ім'я (`04_06 §B.2` BP #14 — фікстура ховає поверхню, не значення).
    # SFC-шлях досяжний: `InsurancePayoutWorker` пише `amount: payout_amount` із
    # `token_type: insurance.token_type`, а `payout_amount` — голий `numeric`.
    it "round-trips EVERY evidence value at SOURCE precision (6dp) so verify stays true" do
      freeze_time do
        now = Time.current.utc
        gp = BigDecimal("1000.123456")
        supply = BigDecimal("7.654321")
        sfc = BigDecimal("42.135791")
        leaf0 = Digest::SHA256.hexdigest(
          described_class.aggregate_payload(
            total_growth_points: gp, total_scc_supply: supply, total_sfc: sfc,
            active_tree_count: 0, chain_hash: "h", anchored_at: now
          )
        )

        record = described_class.create!(
          state_root: MerkleTree.root([ leaf0 ]), total_growth_points: gp,
          total_scc_supply: supply, total_sfc: sfc, active_tree_count: 0,
          chain_hash: "h", anchored_at: now, root_version: 1,
          subtree_roots: [ { "kind" => "aggregate", "root" => leaf0 } ], window_to: now
        ).reload

        expect(record.total_growth_points).to eq(gp)
        expect(record.total_scc_supply).to eq(supply)
        expect(record.total_sfc).to eq(sfc)
        expect(record.verify_state_root).to be true
      end
    end

    it "returns false when state_root does not match" do
      record = described_class.new(
        state_root: "b" * 64,
        total_growth_points: 1000.0,
        chain_hash: "abc",
        anchored_at: Time.current
      )

      expect(record.verify_state_root).to be false
    end

    describe "root_version: 1 (Merkle) [ARCH.12]" do
      let(:now) { Time.current.utc }
      let(:leaf0) do
        Digest::SHA256.hexdigest(
          described_class.aggregate_payload(
            total_growth_points: BigDecimal("1000.5"), total_scc_supply: BigDecimal("7.25"),
            total_sfc: BigDecimal("0"),
            active_tree_count: 0, chain_hash: "test_chain_hash", anchored_at: now
          )
        )
      end
      let(:cluster_root) { MerkleTree.root([ "bafkrei-leaf-1", "bafkrei-leaf-2" ]) }
      let(:tier2) do
        [ { "kind" => "aggregate", "root" => leaf0 },
          { "cluster_id" => 7, "root" => cluster_root } ]
      end

      def build_merkle_record(state_root:, subtree_roots: tier2)
        described_class.new(
          state_root: state_root, total_growth_points: BigDecimal("1000.5"),
          total_scc_supply: BigDecimal("7.25"),
          chain_hash: "test_chain_hash", anchored_at: now,
          root_version: 1, subtree_roots: subtree_roots, window_to: now - 5.minutes
        )
      end

      it "verifies leaf0 against the aggregate formula AND the root against stored subtree_roots" do
        freeze_time do
          record = build_merkle_record(state_root: MerkleTree.root([ leaf0, cluster_root ]))
          expect(record.verify_state_root).to be true
        end
      end

      it "returns false when a stored subtree root is tampered" do
        freeze_time do
          tampered = [ tier2.first, { "cluster_id" => 7, "root" => "f" * 64 } ]
          record = build_merkle_record(
            state_root: MerkleTree.root([ leaf0, cluster_root ]), subtree_roots: tampered
          )
          expect(record.verify_state_root).to be false
        end
      end

      it "returns false when leaf0 does not match the aggregate components (supply tamper)" do
        freeze_time do
          record = build_merkle_record(state_root: MerkleTree.root([ leaf0, cluster_root ]))
          record.total_growth_points = BigDecimal("9999.9")
          expect(record.verify_state_root).to be false
        end
      end

      # [ARCH.97] Дзеркало вище на ДРУГІЙ величині — доказ, що SCC-supply реально
      # входить у leaf0, а не доданий декоративно. Без цього прикладу поле можна було б
      # забути прокинути в payload, і жоден інший пін не почервонів би.
      it "returns false when the SCC supply is tampered (second quantity is load-bearing)" do
        freeze_time do
          record = build_merkle_record(state_root: MerkleTree.root([ leaf0, cluster_root ]))
          record.total_scc_supply = BigDecimal("9999.9")
          expect(record.verify_state_root).to be false
        end
      end

      # [ARCH.97] Дві величини мусять лишатись РІЗНИМИ доданками: якщо колись їх
      # зведуть назад в одну, payload перестане розрізняти «бали» й «монети», а
      # верифікація цього не побачить (обидві сторони рахують однаково).
      it "keeps growth points and minted supply as distinct payload fields" do
        freeze_time do
          payload = described_class.aggregate_payload(
            total_growth_points: BigDecimal("1000.5"), total_scc_supply: BigDecimal("7.25"),
            total_sfc: BigDecimal("0"), active_tree_count: 0,
            chain_hash: "h", anchored_at: now
          )

          expect(payload).to include("1000.5")
          expect(payload).to include("7.25")
          expect(payload.split("|").size).to eq(6)
        end
      end

      it "returns false on blank subtree_roots" do
        record = build_merkle_record(state_root: "a" * 64, subtree_roots: nil)
        expect(record.verify_state_root).to be false
      end

      it "validates subtree_roots + window_to presence for merkle, not for legacy" do
        merkle = described_class.new(root_version: 1)
        legacy = described_class.new(root_version: 0)
        merkle.validate
        legacy.validate
        expect(merkle.errors[:subtree_roots]).to be_present
        expect(merkle.errors[:window_to]).to be_present
        expect(legacy.errors[:subtree_roots]).to be_blank
        expect(legacy.errors[:window_to]).to be_blank
      end
    end
  end

  describe "#etherscan_url" do
    it "returns nil without tx_hash" do
      expect(anchor.etherscan_url).to be_nil
    end

    it "returns etherscan URL with tx_hash" do
      anchor.tx_hash = "0x#{"ab" * 32}"
      expect(anchor.etherscan_url).to eq("https://etherscan.io/tx/0x#{"ab" * 32}")
    end

    # [INF.27] This link is the auditor's reference for the L1 anchor in a lineage proof
    # (`Mrv::LineageReportService`), so a mainnet URL on a testnet slot does not read as
    # "wrong environment" — it reads as "the anchor does not exist". Mainnet above is the
    # fail-closed default; this pins that the slot's declaration actually moves it.
    it "follows the slot's chain declaration" do
      anchor.tx_hash = "0x#{"ab" * 32}"
      previous = ENV.fetch("WEB3_CHAIN_ENV", nil)
      ENV["WEB3_CHAIN_ENV"] = "testnet"
      expect(anchor.etherscan_url).to eq("https://sepolia.etherscan.io/tx/0x#{"ab" * 32}")
    ensure
      previous.nil? ? ENV.delete("WEB3_CHAIN_ENV") : ENV["WEB3_CHAIN_ENV"] = previous
    end
  end

  describe "scopes" do
    before do
      described_class.create!(
        state_root: "a" * 64,
        total_growth_points: 100.0,
        chain_hash: "hash1",
        anchored_at: 2.days.ago,
        status: :confirmed,
        tx_hash: "0x#{"aa" * 32}"
      )
      described_class.create!(
        state_root: "b" * 64,
        total_growth_points: 200.0,
        chain_hash: "hash2",
        anchored_at: 1.day.ago,
        status: :failed,
        error_message: "timeout"
      )
    end

    it ".successful returns only confirmed anchors" do
      expect(described_class.successful.count).to eq(1)
      expect(described_class.successful.first.state_root).to eq("a" * 64)
    end

    it ".recent orders by created_at desc" do
      expect(described_class.recent.first.state_root).to eq("b" * 64)
    end

    it ".in_flight returns only pending/sent anchors from the last week" do
      pending_anchor = described_class.create!(
        state_root: "c" * 64,
        total_growth_points: 300.0,
        chain_hash: "hash3",
        anchored_at: 1.hour.ago,
        status: :pending
      )
      sent_anchor = described_class.create!(
        state_root: "d" * 64,
        total_growth_points: 400.0,
        chain_hash: "hash4",
        anchored_at: 2.hours.ago,
        status: :sent,
        tx_hash: "0x#{"cc" * 32}"
      )

      in_flight = described_class.in_flight
      expect(in_flight).to include(pending_anchor, sent_anchor)
      expect(in_flight).not_to include(described_class.find_by(state_root: "a" * 64))
      expect(in_flight).not_to include(described_class.find_by(state_root: "b" * 64))
    end
  end

  describe ".stuck_sent scope [ARCH.66]" do
    it "returns :sent anchors older than the threshold, excludes fresh and terminal" do
      stuck = create(:ethereum_anchor, :sent)
      stuck.update_column(:updated_at, (described_class::STUCK_SENT_THRESHOLD + 1.hour).ago)
      create(:ethereum_anchor, :sent) # fresh — within threshold → not stuck
      terminal = create(:ethereum_anchor, :confirmed)
      terminal.update_column(:updated_at, 1.day.ago) # terminal never counts

      expect(described_class.stuck_sent).to contain_exactly(stuck)
    end
  end

  describe "[ARCH.66] guarded lifecycle transitions" do
    let(:sent_anchor) { create(:ethereum_anchor, :sent) }

    describe "#confirm!" do
      it "transitions :sent → :confirmed with block_number and gas_used" do
        sent_anchor.confirm!(15_000_000, 47_000)

        expect(sent_anchor.reload).to be_status_confirmed
        expect(sent_anchor.block_number).to eq(15_000_000)
        expect(sent_anchor.gas_used).to eq(47_000)
      end

      it "is idempotent — a second call on a non-:sent anchor is a no-op" do
        sent_anchor.confirm!(15_000_000, 47_000)

        expect(sent_anchor.confirm!(99, 99)).to be false
        expect(sent_anchor.reload.block_number).to eq(15_000_000)
      end

      it "[MEDIUM-A1] confirms FROM :manual_review — operator resolution after etherscan check" do
        sent_anchor.escalate_to_review!("stuck")
        expect(sent_anchor.reload).to be_status_manual_review

        expect(sent_anchor.confirm!(15_000_000, 47_000)).to be_truthy
        expect(sent_anchor.reload).to be_status_confirmed
      end
    end

    describe "#mark_failed!" do
      it "transitions :sent → :failed and truncates the reason to 450 chars" do
        sent_anchor.mark_failed!("x" * 600)

        expect(sent_anchor.reload).to be_status_failed
        expect(sent_anchor.error_message.length).to eq(450)
      end

      it "no-ops on a terminal anchor (already confirmed)" do
        confirmed = create(:ethereum_anchor, :confirmed)

        expect(confirmed.mark_failed!("revert")).to be false
        expect(confirmed.reload).to be_status_confirmed
      end

      it "[MEDIUM-A1] fails FROM :manual_review — operator marks a dropped tx" do
        sent_anchor.escalate_to_review!("stuck")

        expect(sent_anchor.mark_failed!("operator: tx dropped")).to be_truthy
        expect(sent_anchor.reload).to be_status_failed
      end
    end

    describe "#escalate_to_review!" do
      it "transitions :sent → :manual_review and leaves in_flight (unblocks next weekly seal)" do
        sent_anchor.escalate_to_review!("polling exhausted")

        expect(sent_anchor.reload).to be_status_manual_review
        expect(described_class.in_flight).not_to include(sent_anchor)
      end

      it "no-ops on a non-:sent anchor" do
        confirmed = create(:ethereum_anchor, :confirmed)

        expect(confirmed.escalate_to_review!("x")).to be false
        expect(confirmed.reload).to be_status_confirmed
      end
    end

    describe "#escalate_pending_ambiguous! [companion]" do
      it "transitions :pending → :manual_review without tx_hash (resume-landed, hash lost in crash)" do
        pending_anchor = create(:ethereum_anchor) # factory default = :pending, no tx_hash

        expect(pending_anchor.escalate_pending_ambiguous!("nonce 7 already used")).to be_truthy
        expect(pending_anchor.reload).to be_status_manual_review
        expect(pending_anchor.tx_hash).to be_nil
      end

      it "no-ops on a non-:pending anchor (only the resume-ambiguous window escalates here)" do
        expect(sent_anchor.escalate_pending_ambiguous!("x")).to be false
        expect(sent_anchor.reload).to be_status_sent
      end
    end
  end
end
