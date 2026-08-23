# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "open3"

# [E.60 Фаза 1б] Pin-нога: rebuild → звірка → стемп → пін → CAS-термінал;
# регресії: конкурентні копії · retention ≠ mismatch · repair.
RSpec.describe TelemetryArchiveBatchWorker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) do
    w = tree.wallet
    w.update!(balance: 5000)
    allow(w.tree).to receive(:active?).and_return(true)
    w
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    silence_broadcasts!(:wallet_balance, :tree_map)
    allow(Filecoin::ArchiveService).to receive(:pin_json!).and_return("bafkrei_pinned")
  end

  def build_batch!(log_count: 2)
    log_count.times { |i| create(:telemetry_log, tree: tree, created_at: (3 - i).hours.ago) }
    tx = wallet.reload.lock_and_mint!(500, 100)
    group = Mrv::TelemetryArchiveBatchService.group([ tx ], token_type: "carbon_coin").first
    [ group.batch, tx ]
  end

  describe "щасливий шлях" do
    it "стемпить КОЖЕН лог своїм merkle_leaf + спільним archive_root, пінить артефакт, pinned" do
      batch, _tx = build_batch!
      bystander = create(:telemetry_log, tree: tree, created_at: 10.minutes.ago)

      described_class.new.perform(batch.id)

      expect(batch.reload).to be_status_pinned
      expect(batch.ipfs_cid).to eq("bafkrei_pinned")

      stamped = Mrv::TelemetryArchiveBatchService.union_logs([ batch.blockchain_transactions.first ])
      expect(stamped.size).to eq(2)
      stamped.each do |log|
        expect(log.reload.archive_root).to eq(batch.archive_root)
        expect(log.merkle_leaf).to eq(Mrv::TelemetryLeaf.cid_for(log))
      end
      # Сторонній лог (поза вікном) НЕ зачеплено (per-window ізоляція).
      expect(bystander.reload.merkle_leaf).to be_nil

      # (вміст артефакту — window-tuples/instructions — глибоко перевіряє e2e-блок нижче)
      expect(Filecoin::ArchiveService).to have_received(:pin_json!) do |artifact, **_kw|
        expect(artifact[:archive_root]).to eq(batch.archive_root)
        expect(artifact[:leaves].size).to eq(2)
        expect(artifact[:verification_instructions].join).to include("ISSUER-ASSERTED")
      end
    end

    it "ідемпотентний: повторний прогін по pinned = no-op (stale-копія не перетирає термінал)" do
      batch, = build_batch!
      described_class.new.perform(batch.id)
      expect { described_class.new.perform(batch.id) }.not_to change { batch.reload.updated_at }
      expect(Filecoin::ArchiveService).to have_received(:pin_json!).once
    end
  end

  describe "розбіжність кореня" do
    it "мутація payload'а живих логів → mismatch, НІКОЛИ не пінить (integrity-алерт)" do
      batch, tx = build_batch!
      victim = Mrv::TelemetryArchiveBatchService.union_logs([ tx ]).first
      victim.update_column(:z_value, 99.99) # raw-SQL повз seal-guard

      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to receive(:increment).with(labels: { reason: "mismatch" })
      described_class.new.perform(batch.id)

      expect(batch.reload).to be_status_mismatch
      expect(Filecoin::ArchiveService).not_to have_received(:pin_json!)
    end

    it "зникле листя (ретеншн-дроп) → retention_expired, НЕ mismatch" do
      batch, tx = build_batch!
      victim = Mrv::TelemetryArchiveBatchService.union_logs([ tx ]).first
      TelemetryLog.where(id: victim.id, created_at: victim.created_at).delete_all

      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to receive(:increment).with(labels: { reason: "retention_expired" })
      described_class.new.perform(batch.id)

      expect(batch.reload).to be_status_retention_expired
      expect(Filecoin::ArchiveService).not_to have_received(:pin_json!)
    end
  end

  describe "superseded" do
    it "батч без жодного tx → superseded, не пінимо" do
      batch, tx = build_batch!
      tx.update_column(:archive_batch_id, nil) # обхід set-once = симуляція guard-обходу

      described_class.new.perform(batch.id)
      expect(batch.reload).to be_status_superseded
      expect(Filecoin::ArchiveService).not_to have_received(:pin_json!)
    end
  end

  describe "repair-нога (build_failed)" do
    it "пізній rebuild: root + bind незабраних tx + re-enqueue на пін" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = wallet.reload.lock_and_mint!(500, 100)
      trace = TelemetryArchiveBatch.create!(
        token_type: :carbon_coin, status: :build_failed, tx_ids: [ tx.id ], tx_count: 1
      )

      described_class.clear
      described_class.new.perform(trace.id)

      trace.reload
      expect(trace).to be_status_pending
      expect(trace.archive_root).to eq(tx.reload.telemetry_merkle_root)
      expect(tx.archive_batch_id).to eq(trace.id)
      expect(described_class.jobs.size).to eq(1)
    end

    it "tx_entry: wallet-nullified tx (repair-шлях) → tree_did nil, не крах" do
      tx = wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
      )
      tx.update_column(:wallet_id, nil) # ARCH.57 nullify-backstop дозволеного destroy

      entry = described_class.new.send(:tx_entry, tx.reload)
      expect(entry[:tree_did]).to be_nil
      expect(entry[:blockchain_transaction_id]).to eq(tx.id)
    end

    it "невиправний (вікна незабраних tx порожні — windowless) → superseded" do
      tx = wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
      )
      trace = TelemetryArchiveBatch.create!(
        token_type: :carbon_coin, status: :build_failed, tx_ids: [ tx.id ], tx_count: 1
      )

      described_class.new.perform(trace.id)

      expect(trace.reload).to be_status_superseded
      expect(trace.error_message).to include("вікна tx порожні")
    end

    it "невиправний (усі tx уже в інших батчах) → superseded, вихід із reconcile-скоупу" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = wallet.reload.lock_and_mint!(500, 100)
      Mrv::TelemetryArchiveBatchService.group([ tx ], token_type: "carbon_coin") # tx bound
      trace = TelemetryArchiveBatch.create!(
        token_type: :carbon_coin, status: :build_failed, tx_ids: [ tx.id ], tx_count: 1
      )

      described_class.new.perform(trace.id)

      expect(trace.reload).to be_status_superseded
      expect(trace.error_message).to include("repair неможливий")
      expect(TelemetryArchiveBatch.reconcilable).not_to include(trace)
    end

    it "root уже має власника → build_failed лишається слідом (RecordNotUnique-safe)" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = wallet.reload.lock_and_mint!(500, 100)
      owner = Mrv::TelemetryArchiveBatchService.group([ tx ], token_type: "carbon_coin").first.batch
      tx.update_column(:archive_batch_id, nil) # tx «відв'язали», але root-власник живий
      trace = TelemetryArchiveBatch.create!(
        token_type: :carbon_coin, status: :build_failed, tx_ids: [ tx.id ], tx_count: 1
      )

      expect { described_class.new.perform(trace.id) }.not_to raise_error
      expect(trace.reload).to be_status_build_failed
      expect(owner.reload).to be_status_pending
    end
  end

  # [E.60] E2e: артефакт, який пінить воркер, приймає ОФЛАЙН-верифікатор;
  # кожен tamper-клас валить його на ВЛАСНОМУ чеку (не-вакуумні піни).
  describe "e2e: офлайн scripts/verify_archive_bundle.rb" do
    let(:verifier) { Rails.root.join("scripts/verify_archive_bundle.rb").to_s }

    def captured_artifact!
      artifact = nil
      allow(Filecoin::ArchiveService).to receive(:pin_json!) do |content, **_kw|
        artifact = content
        "bafkrei_pinned"
      end
      batch, = build_batch!
      described_class.new.perform(batch.id)
      expect(batch.reload).to be_status_pinned
      JSON.parse(JSON.generate(artifact))
    end

    def run_verifier(data)
      path = Rails.root.join("tmp/archive_bundle_spec_#{Process.pid}.json")
      File.write(path, JSON.generate(data))
      out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
      [ out, status.success? ]
    ensure
      FileUtils.rm_f(path)
    end

    it "чистий артефакт → exit 0; кожен tamper падає на СВОЄМУ чеку" do
      artifact = captured_artifact!

      out, ok = run_verifier(artifact)
      expect(ok).to be(true), "чистий артефакт мав пройти: #{out}"

      # (а) мутація payload → падає на leaf-CID чеку
      tampered = JSON.parse(JSON.generate(artifact))
      tampered["leaves"][0]["payload"]["z_value"] = "999.99"
      out, ok = run_verifier(tampered)
      expect(ok).to be(false)
      expect(out).to include("payload → CID mismatch")

      # (б) підміна root на ЧИСТОМУ артефакті → падає САМЕ на root-чеку
      tampered = JSON.parse(JSON.generate(artifact))
      tampered["archive_root"] = "f" * 64
      out, ok = run_verifier(tampered)
      expect(ok).to be(false)
      expect(out).to include("archive_root mismatch")

      # (в) smuggled leaf: валідний CID, але поза будь-яким вікном → window-binding
      tampered = JSON.parse(JSON.generate(artifact))
      foreign_payload = { "telemetry_log_id" => 999_999, "device_uid" => "SNET-FFFFFFFF",
                          "z_value" => "1.0", "bio_status" => 0,
                          "created_at" => "2020-01-01T00:00:00.000000Z" }
      foreign_cid = Filecoin::CidGenerator.cidv1(foreign_payload)
      tampered["leaves"] << { "payload" => foreign_payload, "leaf_cid" => foreign_cid }
      tampered["archive_root"] = MerkleTree.root(tampered["leaves"].map { |l| l["leaf_cid"] })
      out, ok = run_verifier(tampered)
      expect(ok).to be(false)
      expect(out).to include("smuggled leaf")

      # (г) дубль-ключ JSON → відхилено на вході
      raw = JSON.generate(artifact).sub('"archive_root":', '"archive_root":"' + "e" * 64 + '","archive_root":')
      path = Rails.root.join("tmp/archive_bundle_dup_#{Process.pid}.json")
      File.write(path, raw)
      out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
      FileUtils.rm_f(path)
      expect(status.success?).to be(false)
      expect(out).to match(/відхилено|duplicate/)
    end
  end

  describe "артефакт: tax_rate + непорожня from-межа вікна" do
    it "другий мінт несе from_at/from_id (курсор рушив) і tax_rate у артефакті" do
      create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
      first_tx = wallet.reload.lock_and_mint!(500, 100)
      Mrv::TelemetryArchiveBatchService.group([ first_tx ], token_type: "carbon_coin")

      create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
      second_tx = wallet.reload.lock_and_mint!(500, 100)
      batch = Mrv::TelemetryArchiveBatchService
              .group([ second_tx ], token_type: "carbon_coin", tax_rate: 0.02).first.batch

      artifact = nil
      allow(Filecoin::ArchiveService).to receive(:pin_json!) do |content, **_kw|
        artifact = content
        "bafkrei_second"
      end
      described_class.new.perform(batch.id)

      entry = artifact[:transactions].sole
      expect(entry[:window][:from_at]).to be_present
      expect(entry[:window][:from_id]).to be_present
      expect(artifact[:tax_rate_applied]).to eq("0.02")
    end
  end

  describe "артефакт змішаного батчу (windowed + windowless член)" do
    it "windowless tx_entry несе NULL-вікно (порожній внесок, N:1)" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      windowed = wallet.reload.lock_and_mint!(500, 100)
      windowless = wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
      )
      batch = Mrv::TelemetryArchiveBatchService
              .group([ windowed, windowless ], token_type: "carbon_coin").first.batch

      artifact = nil
      allow(Filecoin::ArchiveService).to receive(:pin_json!) do |content, **_kw|
        artifact = content
        "bafkrei_mixed"
      end
      described_class.new.perform(batch.id)

      entries = artifact[:transactions].index_by { |t| t[:blockchain_transaction_id] }
      expect(entries[windowless.id][:window]).to eq(from_at: nil, from_id: nil, to_at: nil, to_id: nil)
      expect(entries[windowed.id][:window][:to_at]).to be_present
    end
  end

  describe "repair-гонка: конкурент відремонтував першим" do
    it "repair! false мід-флайт → break без bind/enqueue, стан конкурента недоторканий" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      tx = wallet.reload.lock_and_mint!(500, 100)
      trace = TelemetryArchiveBatch.create!(
        token_type: :carbon_coin, status: :build_failed, tx_ids: [ tx.id ], tx_count: 1
      )
      # Конкурентна копія довершила трейс (аж до pinned) МІЖ route-чеком і repair!
      allow(Mrv::TelemetryArchiveBatchService).to receive(:union_logs).and_wrap_original do |m, *args|
        trace.update_columns(status: TelemetryArchiveBatch.statuses[:pinned],
                             archive_root: "c" * 64, ipfs_cid: "bafkrei_rival")
        m.call(*args)
      end

      described_class.clear
      described_class.new.perform(trace.id)

      expect(tx.reload.archive_batch_id).to be_nil       # МІЙ bind не відбувся (break)
      expect(described_class.jobs).to be_empty           # і re-enqueue не потрібен
      expect(trace.reload).to be_status_pinned           # термінал конкурента недоторканий
    end
  end

  describe "retries_exhausted hook" do
    it "no-op на неіснуючому batch_id (batch видалено/фантомний джоб)" do
      expect {
        described_class.sidekiq_retries_exhausted_block.call(
          { "args" => [ -1 ] }, RuntimeError.new("ghost")
        )
      }.not_to raise_error
    end

    it "no-op на вже-pinned батчі (stale-копія не затирає термінал)" do
      batch, = build_batch!
      described_class.new.perform(batch.id)
      expect(batch.reload).to be_status_pinned

      described_class.sidekiq_retries_exhausted_block.call(
        { "args" => [ batch.id ] }, RuntimeError.new("late")
      )
      expect(batch.reload.error_message).to be_nil
      expect(batch).to be_status_pinned
    end

    it "інкрементить pin-метрику і пише error_message на pending-батч" do
      batch, = build_batch!
      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to receive(:increment).with(labels: { reason: "pin" })

      described_class.sidekiq_retries_exhausted_block.call(
        { "args" => [ batch.id ] }, RuntimeError.new("pinata down")
      )
      expect(batch.reload.error_message).to include("pin exhausted")
      expect(batch).to be_status_pending
    end
  end
end
