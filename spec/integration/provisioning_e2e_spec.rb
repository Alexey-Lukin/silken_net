# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# FW.1 — End-to-End Provisioning Flow
# =============================================================================
# Exercises the full Factory-Flashing-equivalent provisioning chain WITHOUT
# stubbing `HardwareKeyService` (unlike the controller request spec, which
# mocks `.provision`). Goal: prove that the API contract documented in
# `docs/04_03_REST_API_v1_Reference.md` §POST /provisioning/register
# and the HKDF design in `docs/03_06_Factory_Flashing_and_Key_Provisioning.md` §2
# hold true end-to-end across controller → service → AR Encryption → DB.
#
# Specifically verifies:
#   * HKDF-SHA256 determinism: the persisted `aes_key_hex` exactly matches an
#     independent re-derivation via `HardwareKeyService.derive_device_key`.
#     This is the firmware-equivalence assertion — backend and firmware MUST
#     derive identical keys for the same `device_uid`, otherwise telemetry
#     decryption breaks silently in production.
#   * HardwareKey row is real (encrypted at rest, 64-hex format, unhexifies
#     to a 32-byte binary key ready for AES-256 CRYP init on STM32).
#   * MaintenanceRecord(installation) is created with DID + hardware_uid
#     embedded in notes, providing an immutable audit trail.
#   * `PeaqRegistrationWorker` is enqueued for trees and NOT for gateways
#     (Tree is the only entity with a peaq DID).
#   * TRL4 lab mode (no `PROVISIONING_MASTER_KEY`) returns `aes_key` in the
#     response; HKDF production mode does NOT (Zero-Trust: key never leaves
#     the backend over the wire).
#   * SEC.11 production guard: production env without the master key MUST
#     raise `SecurityError` and create NO database side effects.
#   * FW.24 firmware fallback magic (`511CEE01`) is rejected with no side
#     effects, regardless of HKDF/TRL4 mode.
#   * Duplicate `hardware_uid` → 409 Conflict with no side effects.
#
# Cross-refs: docs/00_07 FW.1, docs/03_06 §2, docs/04_03 §POST register.
# =============================================================================
RSpec.describe "FW.1 — Provisioning End-to-End Flow", type: :request do
  # Negated matcher used in compound expectations (`change ... .and not_change ...`)
  # to assert atomic rollback / no-side-effect cases. Local to this spec to avoid
  # leaking matcher state across the suite.
  RSpec::Matchers.define_negated_matcher :not_change, :change

  let(:organization) { create(:organization) }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree_family)  { create(:tree_family) }
  let(:forester)     { create(:user, :forester, organization: organization) }
  let(:api_token)    { forester.generate_token_for(:api_access) }
  let(:headers) do
    { "Authorization" => "Bearer #{api_token}", "Accept" => "application/json" }
  end

  before do
    # AR Encryption configuration (matches existing provisioning specs).
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )

    # Suppress ActionCable/Turbo broadcasts triggered by Tree creation.
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(ActionCable.server).to receive(:broadcast)

    # PeaqRegistrationWorker is the only worker we stub — we assert on
    # `perform_async` calls instead of actually executing the worker
    # (which would hit the peaq RPC mock layer and is covered separately).
    allow(PeaqRegistrationWorker).to receive(:perform_async)

    # [ARCH.119] The peaq leg is ACTIVATION-GATED: unconfigured, the controller enqueues
    # NOTHING. Declaring it live here is load-bearing in BOTH directions — without it the
    # positive pins fail (dotenv is dev-only and CI ships no RAILS_MASTER_KEY, so
    # `configured?` is false in test), and the NEGATIVE pins below would go green while
    # proving the gate instead of the device-type / rollback behaviour they name.
    # The gate itself is pinned in spec/requests/api/v1/provisioning_controller_spec.rb.
    allow(Peaq::DidRegistryService).to receive(:configured?).and_return(true)
  end

  # ---------------------------------------------------------------------------
  # 1. HKDF Mode — Zero-Trust key derivation [SEC.11 sole mode]
  # ---------------------------------------------------------------------------
  describe "HKDF mode (PROVISIONING_MASTER_KEY set)" do
    let(:master_key) { "e2e-master-key-32bytes-hkdf-test" }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(master_key)
    end

    context "when device_type is tree" do
      # [FW.54] 24-hex кремнієвий UID (golden g1) → деривований DID
      let(:hardware_uid) { "0039002F3138511538323634" }
      let(:expected_did) { "SNET-80B12004" }
      let(:tree_params) do
        {
          provisioning: {
            hardware_uid: hardware_uid,
            device_type: "tree",
            cluster_id: cluster.id,
            family_id: tree_family.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "creates Tree, HardwareKey, MaintenanceRecord atomically and returns Zero-Trust JSON body" do
        expect {
          post "/provisioning/register", params: tree_params, headers: headers, as: :json
        }.to change(Tree, :count).by(1)
         .and change(HardwareKey, :count).by(1)
         .and change(MaintenanceRecord, :count).by(1)

        expect(response).to have_http_status(:created)

        body = response.parsed_body
        expect(body["did"]).to eq(expected_did)
        expect(body["key_derivation"]).to eq("hkdf-sha256")

        # Zero-Trust: AES key MUST NOT be returned over the wire in HKDF mode.
        expect(body).not_to have_key("aes_key")
        expect(body).not_to have_key("warning")
      end

      it "enqueues PeaqRegistrationWorker and records the installation MaintenanceRecord" do
        post "/provisioning/register", params: tree_params, headers: headers, as: :json
        expect(response).to have_http_status(:created)

        tree = Tree.find_by!(did: expected_did)
        expect(PeaqRegistrationWorker).to have_received(:perform_async).with(tree.id)

        record = MaintenanceRecord.find_by!(maintainable: tree)
        expect(record.action_type).to eq("installation")
        expect(record.user).to eq(forester)
        expect(record.notes).to include(expected_did)
        expect(record.notes).to include(hardware_uid)
      end

      it "persists the LoRa AES-128 key derived deterministically from PROVISIONING_MASTER_KEY + DID [post-ARCH.42]" do
        post "/provisioning/register", params: tree_params, headers: headers, as: :json
        expect(response).to have_http_status(:created)

        hw_key = HardwareKey.find_by!(device_uid: expected_did)

        # Firmware-equivalence assertion: re-derive independently and compare.
        # Post-ARCH.42 Variant B (2026-05-23): Tree LoRa channel — AES-128 (16 bytes,
        # info "silken-aes-128-lora-key"); вибір ARCH.42, не SE-constraint (SE = SE050 — 03_05 §3.7).
        # If this ever fails, backend ↔ firmware AES keys would diverge silently
        # and decryption of telemetry would break in production. See SEC.11 + ARCH.42.
        expected_key = HardwareKeyService.derive_lora_key(expected_did)
        expect(hw_key.aes_key_hex).to eq(expected_key)

        # 32 uppercase hex chars (AES-128 post-ARCH.42, see HardwareKey conditional validator).
        expect(hw_key.aes_key_hex).to match(/\A[0-9A-F]{32}\z/)

        # binary_key must unhexify to exactly 16 bytes (firmware loads this into
        # CRYP_KEYSIZE_128B via Load_AES_Key() — see 03_06 §2 post-ARCH.42).
        expect(hw_key.binary_key.bytesize).to eq(16)
      end

      it "produces the same key for identical UID and different keys for different UIDs (HKDF determinism)" do
        key_a1 = HardwareKeyService.derive_device_key("SNET-DEADBEEF")
        key_a2 = HardwareKeyService.derive_device_key("SNET-DEADBEEF")
        key_b  = HardwareKeyService.derive_device_key("SNET-CAFEBABE")

        expect(key_a1).to eq(key_a2)
        expect(key_a1).not_to eq(key_b)
      end
    end

    context "when device_type is gateway with Ed25519 public key" do
      let(:gateway_uid)     { "SNET-Q-AABB1122" }
      let(:ed25519_key_hex) { SecureRandom.hex(32) } # 64 hex chars = 32 bytes
      let(:gateway_params) do
        {
          provisioning: {
            hardware_uid: gateway_uid,
            device_type: "gateway",
            cluster_id: cluster.id,
            latitude: 49.4285,
            longitude: 32.0620,
            ed25519_public_key: ed25519_key_hex
          }
        }
      end

      it "creates Gateway + HardwareKey, persists Ed25519 key, and does NOT enqueue PeaqRegistrationWorker" do
        expect {
          post "/provisioning/register", params: gateway_params, headers: headers, as: :json
        }.to change(Gateway, :count).by(1)
         .and change(HardwareKey, :count).by(1)

        expect(response).to have_http_status(:created)

        body = response.parsed_body
        expect(body["did"]).to eq(gateway_uid)
        expect(body["key_derivation"]).to eq("hkdf-sha256")
        expect(body).not_to have_key("aes_key")

        hw_key = HardwareKey.find_by!(device_uid: gateway_uid)
        expect(hw_key.ed25519_public_key_hex).to eq(ed25519_key_hex)

        # Tree-only: gateways have no peaq DID, no worker enqueued.
        expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. SEC.11 — Hard cutover guard
  # ---------------------------------------------------------------------------
  # Without PROVISIONING_MASTER_KEY backend would diverge silently from
  # firmware HKDF derivation. There is no SecureRandom fallback (SEC.11
  # hard cutover): provisioning MUST raise and create no rows.
  describe "SEC.11 — without PROVISIONING_MASTER_KEY" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)
    end

    let(:tree_params) do
      {
        provisioning: {
          hardware_uid: "0039002F313851150000AA01",
          device_type: "tree",
          cluster_id: cluster.id,
          family_id: tree_family.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }
    end

    it "raises SecurityError and creates no Tree/HardwareKey/MaintenanceRecord, enqueues no worker" do
      # SecurityError inherits from Exception (NOT StandardError), so the
      # controller's `rescue StandardError` does NOT catch it. The critical
      # guarantee we assert here is that the Active Record transaction is
      # rolled back: no Tree, no HardwareKey, no MaintenanceRecord rows,
      # no peaq enqueue.
      expect {
        expect {
          post "/provisioning/register", params: tree_params, headers: headers, as: :json
        }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
      }.to not_change(Tree, :count)
       .and not_change(HardwareKey, :count)
       .and not_change(MaintenanceRecord, :count)

      expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. [FW.54 Вісь 2] FW.24-guard знято — суфікс 511CEE01 більше не магічний
  # ---------------------------------------------------------------------------
  # Firmware не емітує fallback-константу (DID = f(UID), did_derive.h);
  # під новою схемою цей суфікс — легітимна точка DID-простору, тож e2e
  # пінує повний happy-path для нього, включно з крипто-пропискою.
  describe "hardware_uid ending with retired FW.24 magic provisions normally" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("e2e-master-key-32bytes-hkdf-test")
    end

    let(:magic_params) do
      {
        provisioning: {
          hardware_uid: "0039002F31385115511CEE01",
          device_type: "tree",
          cluster_id: cluster.id,
          family_id: tree_family.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }
    end

    it "creates Tree + HardwareKey and enqueues Web3 registration" do
      expect {
        post "/provisioning/register", params: magic_params, headers: headers, as: :json
      }.to change(Tree, :count).by(1)
       .and change(HardwareKey, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(PeaqRegistrationWorker).to have_received(:perform_async)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Duplicate hardware_uid — 409 Conflict, no side effects
  # ---------------------------------------------------------------------------
  describe "duplicate hardware_uid" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("e2e-master-key-32bytes-hkdf-test")
    end

    # [FW.54] Guard живе на ДЕРИВОВАНОМУ DID (до FW.54 перевіряв сирий
    # hardware_uid — для дерев ніколи не спрацьовував: provision пише "SNET-…").
    let(:dup_uid) { "0039002F3138511538323634" } # golden g1
    let!(:existing) do
      HardwareKey.create!(
        device_uid: SilkenNet::DidDerivation.wire_did_from_uid_hex(dup_uid),
        aes_key_hex: SecureRandom.hex(32).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )
    end

    let(:dup_params) do
      {
        provisioning: {
          hardware_uid: dup_uid,
          device_type: "tree",
          cluster_id: cluster.id,
          family_id: tree_family.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }
    end

    it "returns 409 Conflict and creates no Tree/MaintenanceRecord, enqueues no worker" do
      expect {
        post "/provisioning/register", params: dup_params, headers: headers, as: :json
      }.to not_change(Tree, :count)
       .and not_change(HardwareKey, :count)
       .and not_change(MaintenanceRecord, :count)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to include("already registered")
      expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
    end
  end
end
