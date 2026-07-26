# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "rake"

# [SEC.3] End-to-end Factory Flashing exercise — exercises the Rake-task
# trio (flash → approve → execute) against an in-memory dry-run executor
# and verifies firmware-equivalence with the public provisioning HKDF.
#
# We bypass the real `STM32_Programmer_CLI` subprocess via the dry-run
# Executor (default). The "did the right key land in HardwareKey?" check
# replays `HardwareKeyService.derive_lora_key(device_uid)` and asserts it
# matches `HardwareKey#aes_key_hex` byte-for-byte — i.e. exactly what
# firmware would derive from the same PROVISIONING_MASTER_KEY.
RSpec.describe "Factory Flashing E2E (Rake trio)", :aggregate_failures do
  # Rake task registry is process-global, not per-spec DB state, so loading
  # it once across the file is safe. We use Rails.application.load_tasks to
  # populate the default Rake.application (lib/tasks/*.rake) idempotently —
  # subsequent calls become no-ops because each .rake file is already in
  # $LOADED_FEATURES.
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("factory:flash")
  end

  # The default spec_helper master key is intentionally on the WeakKeyDetector
  # placeholder list (SEC.9). For E2E flows that exercise the real EnvAdapter
  # we need a "strong-looking" key — SecureRandom hex passes both the
  # placeholder and degenerate-pattern checks.
  around do |example|
    original = ENV["PROVISIONING_MASTER_KEY"]
    ENV["PROVISIONING_MASTER_KEY"] = SecureRandom.hex(32)
    example.run
  ensure
    ENV["PROVISIONING_MASTER_KEY"] = original
  end

  let(:operator)   { create(:user, :super_admin) }
  let(:supervisor) { create(:user, :admin, organization: operator.organization) }
  # golden g1: UID → SNET-80B12004 (did_derivation_spec ↔ test_did_derive.c)
  let(:g1_uid) { "0039002F3138511538323634" }
  # [FW.54] Дерево з кремнієвим паспортом — re-flash по DID легальний
  let(:tree) { create(:tree, did: "SNET-80B12004", silicon_uid_hex: g1_uid) }

  def invoke(task_name, *args)
    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke(*args)
  end

  after do
    ENV.delete("SUPERVISOR_PASSWORD")
    ENV.delete("CLUSTER_ID")
    ENV.delete("TREE_FAMILY_ID")
  end

  it "flash(UID) → approve → execute: one-pass — Tree створено з деривованим DID, ключі derivation-matching" do
    operator; supervisor
    cluster = create(:cluster)

    # Stub STDOUT so rake `puts` doesn't pollute spec output.
    allow($stdout).to receive(:puts)

    # [FW.54] У позиції device_uid — 24-hex кремнієвий UID; резолвер створює
    # Tree (CLUSTER_ID/TREE_FAMILY_ID env) і сесія отримує деривований DID.
    ENV["CLUSTER_ID"]     = cluster.id.to_s
    ENV["TREE_FAMILY_ID"] = create(:tree_family).id.to_s

    expect {
      invoke("factory:flash",
             g1_uid, "BATCH-E2E", "A",
             operator.id.to_s, supervisor.id.to_s, "fw-e2e-1.0")
    }.to change(ProvisioningSession, :count).by(1)
       .and change(Tree, :count).by(1)

    expect(Tree.find_by!(did: "SNET-80B12004"))
      .to have_attributes(silicon_uid_hex: g1_uid, cluster_id: cluster.id)

    session = ProvisioningSession.order(:id).last
    expect(session).to have_attributes(state: "pending", device_uid: "SNET-80B12004")

    ENV["SUPERVISOR_PASSWORD"] = "password12345" # supervisor's own password (2-Person Rule, SEC.3)
    invoke("factory:approve", session.id.to_s)
    expect(session.reload.state).to eq("supervisor_approved")

    expect {
      invoke("factory:execute", session.id.to_s)
    }.to change(HardwareKey, :count).by(1)
       .and change(AuditLog.where(action: "factory_flash"), :count).by(1)

    session.reload
    expect(session.state).to eq("completed")
    expect(session.error_message).to be_nil

    hw_key = HardwareKey.find_by!(device_uid: "SNET-80B12004")
    expect(hw_key.aes_key_hex.length).to eq(32) # 16-byte LoRa key for Tree
    expect(hw_key.lorenz_seed_hex).to be_present

    # Firmware-equivalence — the AES key persisted MUST match a fresh
    # HKDF derivation from the same PROVISIONING_MASTER_KEY.
    expect(hw_key.aes_key_hex).to eq(HardwareKeyService.derive_lora_key("SNET-80B12004"))

    # [FW.54] AuditLog несе кремнієвий паспорт поряд з DID
    expect(AuditLog.where(action: "factory_flash").order(:id).last.metadata["silicon_uid_hex"]).to eq(g1_uid)
  end

  it "flash по голому DID дерева БЕЗ паспорта → abort (footgun post-FW.54)" do
    allow($stdout).to receive(:puts)
    operator; supervisor
    legacy = create(:tree) # без silicon_uid_hex

    expect {
      invoke("factory:flash",
             legacy.did, "BATCH-LEGACY", "A",
             operator.id.to_s, supervisor.id.to_s, "fw-e2e-1.0")
    }.to raise_error(SystemExit)
    expect(ProvisioningSession.where(device_uid: legacy.did)).to be_empty
  end

  it "refuses to execute when supervisor has not approved" do
    allow($stdout).to receive(:puts)
    operator; supervisor; tree

    invoke("factory:flash",
           tree.did, "BATCH-NO-APPROVE", "A",
           operator.id.to_s, supervisor.id.to_s, "fw-e2e-1.0")
    session = ProvisioningSession.order(:id).last

    expect {
      invoke("factory:execute", session.id.to_s)
    }.to raise_error(FactoryFlashing::Session::PreflightError, /supervisor_approved/)

    expect(HardwareKey.where(device_uid: tree.did)).to be_empty
  end

  it "rejects approval without the supervisor's password [SEC.3]" do
    allow($stdout).to receive(:puts)
    operator; supervisor; tree
    invoke("factory:flash",
           tree.did, "BATCH-SUP", "A",
           operator.id.to_s, supervisor.id.to_s, "fw-e2e-1.0")
    session = ProvisioningSession.order(:id).last

    # wrong supervisor password → abort (SystemExit); session stays pending
    ENV["SUPERVISOR_PASSWORD"] = "definitely-wrong"
    expect { invoke("factory:approve", session.id.to_s) }.to raise_error(SystemExit)
    expect(session.reload.state).to eq("pending")

    # missing password → abort too
    ENV.delete("SUPERVISOR_PASSWORD")
    expect { invoke("factory:approve", session.id.to_s) }.to raise_error(SystemExit)
    expect(session.reload.state).to eq("pending")
  end
end
