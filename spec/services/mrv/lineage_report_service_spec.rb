# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mrv::LineageReportService do
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
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  def mint_confirmed!(points = 500)
    tx = wallet.reload.lock_and_mint!(points, 100)
    tx.process!
    tx.mark_as_sent!("0x#{SecureRandom.hex(32)}")
    tx.confirm!(12_345, 0.01)
    tx.reload
  end

  def anchor_confirmed!
    root_data = Ethereum::StateAnchorService.new.generate_state_root
    EthereumAnchor.create!(
      root_data.merge(status: :confirmed, tx_hash: "0x#{SecureRandom.hex(32)}", block_number: 1)
    )
  end

  def bundle
    described_class.call(organization: organization, from: 1.day.ago, to: 1.minute.from_now)
  end

  it "builds a self-contained bundle whose proofs the OFFLINE verifier accepts; tamper → exit 1" do
    log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    tx = mint_confirmed!
    anchor = anchor_confirmed!

    result = bundle
    expect(result[:credits].size).to eq(1)
    credit = result[:credits].first
    expect(credit[:tx][:id]).to eq(tx.id)
    expect(credit[:seal]).to eq("sealed")
    expect(credit[:telemetry_merkle_root]).to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(log) ]))

    leaf = credit[:leaves].first
    expect(leaf[:telemetry_log_id]).to eq(log.id)
    expect(leaf[:anchor_proof][:status]).to eq("anchored")
    expect(leaf[:anchor_proof][:anchor][:state_root]).to eq(anchor.state_root)

    path = Rails.root.join("tmp/lineage_bundle_spec_#{Process.pid}.json")
    File.write(path, JSON.generate(result))
    verifier = Rails.root.join("scripts/verify_lineage_bundle.rb").to_s
    expect(system(RbConfig.ruby, verifier, path.to_s, out: File::NULL)).to be(true), "верифікатор мав пройти"

    tampered = JSON.parse(File.read(path))
    tampered["credits"][0]["leaves"][0]["payload"]["z_value"] = "999.99"
    File.write(path, JSON.generate(tampered))
    expect(system(RbConfig.ruby, verifier, path.to_s, out: File::NULL)).to be(false), "payload-tamper мав дати exit 1"

    # Review-фікс (fable MAJOR): mint-root тепер ПЕРЕВІРЯЄТЬСЯ — підміна набору листя
    # sealed-кредиту (чужий root) мусить валити верифікатор, не братись на віру.
    tampered_root = JSON.parse(File.read(path))
    tampered_root["credits"][0]["leaves"][0]["payload"]["z_value"] = "23.45" # відкотити payload
    tampered_root["credits"][0]["telemetry_merkle_root"] = "ff" * 32
    File.write(path, JSON.generate(tampered_root))
    expect(system(RbConfig.ruby, verifier, path.to_s, out: File::NULL)).to be(false), "root-tamper мав дати exit 1"
  ensure
    FileUtils.rm_f(path) if path
  end

  it "marks leaves newer than the last confirmed anchor as pending_anchor (чесно, не фейл)" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof]).to eq({ status: "pending_anchor" })
  end

  it "scopes credits to the given organization only (IDOR)" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    stranger = create(:organization)

    result = described_class.call(organization: stranger, from: 1.day.ago, to: 1.minute.from_now)
    expect(result[:credits]).to be_empty
  end

  it "inherits failed-attempt windows into the next successful credit (чесна межа (г))" do
    old_log = create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
    failed_tx = wallet.lock_and_mint!(300, 100)
    failed_tx.fail!("rpc down")
    new_log = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
    tx = mint_confirmed!(600)

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx.id }
    expect(credit[:inherited_windows].map { |w| w[:tx_id] }).to eq([ failed_tx.id ])
    own = credit[:leaves].select { |l| l[:window_source] == tx.id }.map { |l| l[:telemetry_log_id] }
    inherited = credit[:leaves].select { |l| l[:window_source].nil? }.map { |l| l[:telemetry_log_id] }
    expect(own).to eq([ new_log.id ])
    expect(inherited).to eq([ old_log.id ])
  end

  it "marks leaves unprovable_regrouped when the tree moved cluster after anchoring" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    tree.update!(cluster: create(:cluster, organization: organization))

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof][:status]).to eq("unprovable_regrouped")
  end

  it "marks unprovable_regrouped when the tree moved into a cluster that WAS anchored (subroot mismatch)" do
    other_tree = create(:tree, cluster: create(:cluster, organization: organization))
    create(:telemetry_log, tree: other_tree, created_at: 2.hours.ago)
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    tree.update!(cluster: other_tree.cluster) # entry існує, але recompute ≠ stored

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof][:status]).to eq("unprovable_regrouped")
  end

  it "serializes an empty-window credit honestly (unsealed, nil window bounds)" do
    tx = mint_confirmed! # жодного лога → window_upper nil

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx.id }
    expect(credit[:seal]).to eq("unsealed")
    expect(credit[:window]).to eq({ from_at: nil, from_id: nil, to_at: nil, to_id: nil })
    expect(credit[:leaves]).to be_empty
  end

  it "inherits only failed attempts AFTER the previous confirmed mint" do
    create(:telemetry_log, tree: tree, created_at: 4.hours.ago)
    mint_confirmed! # перший confirmed — його вікно спожито
    failed_between = wallet.reload.lock_and_mint!(300, 100)
    failed_between.fail!("boom")
    create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
    tx2 = mint_confirmed!(600)

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx2.id }
    expect(credit[:inherited_windows].map { |w| w[:tx_id] }).to eq([ failed_between.id ])
  end

  it "proves against a second anchor whose window chains from the first (window_from present)" do
    create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    # created_at МУСИТЬ бути > anchor1.window_to (= now−GRACE): у проді created_at
    # ставиться при INSERT, тож рядок не може «просочитись» у вже-заякорене вікно.
    late_log = create(:telemetry_log, tree: tree, created_at: 2.minutes.ago)
    travel_to(1.hour.from_now) do
      tx2 = mint_confirmed!(600)
      anchor2 = anchor_confirmed!
      expect(anchor2.window_from).to be_present

      credit = bundle[:credits].find { |c| c[:tx][:id] == tx2.id }
      leaf = credit[:leaves].find { |l| l[:telemetry_log_id] == late_log.id }
      expect(leaf[:anchor_proof][:status]).to eq("anchored")
      expect(leaf[:anchor_proof][:anchor][:state_root]).to eq(anchor2.state_root)
    end
  end
end
