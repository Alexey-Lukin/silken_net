# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardwareKeyService, type: :service do
  let(:tree_family) { create(:tree_family) }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  # Post-ARCH.42: Tree-shaped HardwareKey має 32 hex (16-byte AES-128 LoRa key).
  let(:original_key) { SecureRandom.hex(16).upcase }

  before do
    # Configure ActiveRecord Encryption for tests
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )
    allow(KeyRotationDownlinkWorker).to receive(:perform_async)
  end

  # [FW.17] Tree-ротація гейтована на CCM-flip; тут відкриваємо для тестів шляху.
  def open_ratchet_gate!
    allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(true)
  end

  describe "#rotate!" do
    let!(:hardware_key) do
      HardwareKey.create!(
        device_uid: tree.did,
        aes_key_hex: original_key,
        previous_aes_key_hex: nil,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )
    end

    it "successfully rotates the key when no previous rotation is pending" do
      open_ratchet_gate!
      service = described_class.new(tree)
      new_key = service.rotate!

      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(new_key)
      expect(hardware_key.previous_aes_key_hex).to eq(original_key)
      expect(hardware_key.rotated_at).not_to be_nil
    end

    # [ARCH.57] Ротація → chain-only audit; key-матеріал у metadata НЕ потрапляє.
    it "records the rotation into the audit chain without key material" do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silken.net",
                                  first_name: "Oracle", last_name: "Executioner")
      open_ratchet_gate!

      expect { described_class.new(tree).rotate! }
        .to change { AuditLogWorker.jobs.size }.by(1)

      job = AuditLogWorker.jobs.last
      attrs = job["args"].first
      expect(attrs["action"]).to eq("hardware_key_rotated")
      expect(attrs["metadata"]).to include("mode" => "ratchet", "device_uid" => tree.did)
      expect(attrs["metadata"].values.join).not_to include(hardware_key.reload.aes_key_hex)
      expect(job["args"][1]).to be false
    end

    # [FW.17] Tree-шлях — ратчет, не SecureRandom: новий ключ детермінований
    # (K_{v+1} = KeyRatchet), версія інкрементована, 0x9E поставлено в чергу.
    it "derives the Tree key via Hash-Ratchet and dispatches CMD_ROTATE_KEY" do
      open_ratchet_gate!
      expected = Cryptography::KeyRatchet.advance_hex(
        original_key, Cryptography::KeyRatchet.did_to_u32(tree.did), from: 0, to: 1
      )

      new_key = described_class.new(tree).rotate!

      expect(new_key).to eq(expected)
      hardware_key.reload
      expect(hardware_key.key_version).to eq(1)
      expect(KeyRotationDownlinkWorker).to have_received(:perform_async).with(tree.did, 1)
    end

    # Golden-KAT (K0=000102..0F, DID=0xDEADBEEF → K1) — той самий вектор, що
    # firmware/test/test_key_ratchet.c: пінує крос-шаровий wiring did_to_u32+advance.
    it "matches the firmware golden KAT through the full service path" do
      open_ratchet_gate!
      kat_tree = create(:tree, did: "SNET-DEADBEEF", cluster: cluster, tree_family: tree_family)
      HardwareKey.create!(
        device_uid: kat_tree.did,
        aes_key_hex: "000102030405060708090A0B0C0D0E0F",
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      new_key = described_class.new(kat_tree).rotate!

      expect(new_key).to eq("C2A8861DEF01E2A944D3CD989A7CF117")
    end

    it "refuses Tree rotation while the FW17 gate is closed (no DB change, no dispatch)" do
      service = described_class.new(tree)

      expect { service.rotate! }
        .to raise_error(HardwareKeyService::RatchetGateClosedError, /FW17_RATCHET_DOWNLINK_ENABLED/)

      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(original_key)
      expect(hardware_key.key_version).to eq(0)
      expect(KeyRotationDownlinkWorker).not_to have_received(:perform_async)
    end

    it "raises error when previous rotation is still pending (dead-end protection)" do
      # Same byte-length as the active key (Tree LoRa AES-128 = 16 bytes / 32 hex)
      hardware_key.update!(previous_aes_key_hex: SecureRandom.hex(16).upcase)

      service = described_class.new(tree)
      expect {
        service.rotate!
      }.to raise_error(HardwareKeyService::RotationPendingError, /Ротація заблокована/)

      # Key should remain unchanged
      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(original_key)
    end

    # [ARCH.59] Дзеркало знятої «атомарності»: enqueue стоїть ПІСЛЯ коміту, тож
    # мертвий Redis більше не відкочує ротацію. Це вибір НАПРЯМКУ відмови, а не
    # послаблення: стан, що лишається, тракт лікує сам, і другу половину доказу
    # несе `spec/services/downlink/pending_queue_service_spec.rb` («derivable з
    # Dual-Key Grace») — шов між ними рівно один, колонка нижче.
    it "survives a failed downlink enqueue and arms the Grace backstop" do
      open_ratchet_gate!
      service = described_class.new(tree)

      # Simulate Redis/Sidekiq failure at 0x9E enqueue time
      allow(KeyRotationDownlinkWorker).to receive(:perform_async).and_raise(StandardError.new("Redis unavailable"))

      expect {
        service.rotate!
      }.to raise_error(StandardError, /Redis unavailable/)

      hardware_key.reload
      expect(hardware_key.aes_key_hex).not_to eq(original_key)
      expect(hardware_key.key_version).to eq(1)
      # Саме це поле читає `Downlink::PendingQueueService#key_rotation_payload`:
      # непорожнє = незавершена ротація доїде 0x9E на наступному poll'і Королеви.
      expect(hardware_key.previous_aes_key_hex).to eq(original_key)
    end

    it "allows rotation after grace period is cleared" do
      open_ratchet_gate!
      # First rotation
      service = described_class.new(tree)
      service.rotate!

      # Clear grace period (simulating device confirmation)
      hardware_key.reload
      hardware_key.clear_grace_period!

      # Second rotation should now succeed
      expect {
        service.rotate!
      }.not_to raise_error
    end
  end

  describe ".provision" do
    # Post-ARCH.42: Tree provision повертає 32-hex AES-128 LoRa ключ.
    it "creates a HardwareKey and returns hex key" do
      result = described_class.provision(tree)

      expect(result).to be_a(String)
      expect(result.length).to eq(32) # 16 bytes = 32 hex chars (AES-128 LoRa, post-ARCH.42)
      expect(result).to match(/\A[0-9A-F]+\z/)

      hw_key = HardwareKey.find_by(device_uid: tree.did)
      expect(hw_key).to be_present
      expect(hw_key.aes_key_hex).to eq(result)
    end

    it "uses uid for gateway devices" do
      gateway = create(:gateway, cluster: cluster)

      result = described_class.provision(gateway)

      hw_key = HardwareKey.find_by(device_uid: gateway.uid)
      expect(hw_key).to be_present
      expect(hw_key.aes_key_hex).to eq(result)
    end

    context "with PROVISIONING_MASTER_KEY (HKDF mode)" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("test-master-key-for-hkdf-derive!")
      end

      it "derives deterministic key from device_uid via HKDF" do
        result1 = described_class.derive_device_key(tree.did)
        result2 = described_class.derive_device_key(tree.did)

        expect(result1).to eq(result2) # Deterministic: same UID = same key
        expect(result1.length).to eq(64)
        expect(result1).to match(/\A[0-9A-F]+\z/)
      end

      it "derives different keys for different devices" do
        gateway = create(:gateway, cluster: cluster)

        key_tree = described_class.derive_device_key(tree.did)
        key_gateway = described_class.derive_device_key(gateway.uid)

        expect(key_tree).not_to eq(key_gateway)
      end
    end

    context "without PROVISIONING_MASTER_KEY [SEC.11 hard cutover]" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)
      end

      it "raises SecurityError — no SecureRandom fallback" do
        expect {
          described_class.derive_device_key("DEVICE-A")
        }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
      end

      it "blocks .provision (no HardwareKey created)" do
        expect {
          described_class.provision(tree)
        }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)

        expect(HardwareKey.find_by(device_uid: tree.did)).to be_nil
      end
    end
  end

  # [FW.2 гейт (в)] Cluster control-plane ключ (KEYB) — двоключова модель
  describe ".derive_broadcast_key" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("test-master-key-for-hkdf-derive!")
    end

    it "derives a deterministic 16-byte (32-hex) key per cluster" do
      k1 = described_class.derive_broadcast_key(cluster.id)
      k2 = described_class.derive_broadcast_key(cluster.id)

      expect(k1).to eq(k2)
      expect(k1.length).to eq(32) # AES-128
      expect(k1).to match(/\A[0-9A-F]+\z/)
    end

    it "isolates clusters — різні cluster_id дають різні KEYB" do
      expect(described_class.derive_broadcast_key(1)).not_to eq(described_class.derive_broadcast_key(2))
    end

    it "is domain-separated from the per-device session key on the same salt input" do
      # Навіть якби DID текстуально збігся з "cluster:<id>", info-string розводить домени
      collision_salt = "cluster:#{cluster.id}"
      session_key = described_class.derive_lora_key(collision_salt)
      expect(described_class.derive_broadcast_key(cluster.id)).not_to eq(session_key)
    end

    it "is domain-separated from K_ota (same salt domain, different info)" do
      k_ota = OtaHmacKeyService.fetch_for(cluster.id)
      keyb  = described_class.derive_broadcast_key(cluster.id)
      expect(k_ota).not_to start_with(keyb)
    end

    it "raises without cluster_id" do
      expect { described_class.derive_broadcast_key(nil) }.to raise_error(ArgumentError, /cluster_id/)
    end

    it "raises SecurityError without a master key [SEC.11]" do
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)
      expect {
        described_class.derive_broadcast_key(cluster.id)
      }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
    end
  end

  # Iotex Ed25519 attestation seed — the per-uplink hot path (W3bstream signs
  # every telemetry log). Cached in-process to spare the crown-jewel (SEC.22).
  describe ".derive_iotex_seed" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("test-master-key-for-hkdf-derive!")
    end

    it "derives a deterministic 32-byte (64-hex) seed per device" do
      s1 = described_class.derive_iotex_seed("DEVICE-A")
      s2 = described_class.derive_iotex_seed("DEVICE-A")

      expect(s1).to eq(s2)
      expect(s1.length).to eq(64) # 32 bytes for Ed25519
      expect(s1).to match(/\A[0-9A-F]+\z/)
    end

    it "isolates devices — different device_uid → different seed" do
      expect(described_class.derive_iotex_seed("DEVICE-A"))
        .not_to eq(described_class.derive_iotex_seed("DEVICE-B"))
    end

    it "is domain-separated from the CoAP device key on the same salt input" do
      expect(described_class.derive_iotex_seed("DEVICE-A"))
        .not_to eq(described_class.derive_device_key("DEVICE-A"))
    end

    # [SEC.22] The whole point: a cache hit must NOT re-touch the master key via HKDF.
    it "memoizes the ENV-path derivation (second call touches no crown-jewel)" do
      described_class.derive_iotex_seed("DEVICE-A") # warm: miss → one HKDF call

      expect(OpenSSL::KDF).not_to receive(:hkdf)
      expect(described_class.derive_iotex_seed("DEVICE-A").length).to eq(64)
    end

    # [SEC.3 DI] Explicit master_key: derives fresh and must NOT poison the shared
    # (info, uid) cache slot — otherwise the ENV path would serve the DI seed.
    it "bypasses the cache for an explicit master_key: without poisoning the ENV path" do
      di_key = "di-alive-proof-master-key-distinct"
      via_param = described_class.derive_iotex_seed("DEVICE-A", master_key: di_key)
      via_env   = described_class.derive_iotex_seed("DEVICE-A")

      expect(via_param).not_to eq(via_env)
      oracle = OpenSSL::KDF.hkdf(
        "test-master-key-for-hkdf-derive!", salt: "DEVICE-A",
        info: described_class::IOTEX_HKDF_INFO, length: described_class::IOTEX_SEED_SIZE_BYTES,
        hash: "SHA256"
      ).unpack1("H*").upcase
      expect(via_env).to eq(oracle)
    end

    it "raises SecurityError without a master key [SEC.11]" do
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)
      expect { described_class.derive_iotex_seed("DEVICE-A") }
        .to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
    end
  end

  describe ".rotate" do
    let!(:hardware_key) do
      HardwareKey.create!(
        device_uid: tree.did,
        aes_key_hex: original_key,
        previous_aes_key_hex: nil,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )
    end

    it "finds device by DID (Tree) and calls rotate!" do
      open_ratchet_gate!
      new_key = described_class.rotate(tree.did)

      expect(new_key).to be_a(String)
      # Post-ARCH.42: Tree LoRa AES-128 rotation повертає 32-hex (16 bytes).
      expect(new_key.length).to eq(32)

      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(new_key)
      expect(hardware_key.previous_aes_key_hex).to eq(original_key)
    end

    it "finds device by UID (Gateway) and calls rotate!" do
      gateway = create(:gateway, cluster: cluster)
      gw_key_hex = SecureRandom.hex(32).upcase
      gw_hw_key = HardwareKey.create!(
        device_uid: gateway.uid,
        aes_key_hex: gw_key_hex,
        previous_aes_key_hex: nil,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      new_key = described_class.rotate(gateway.uid)

      gw_hw_key.reload
      expect(gw_hw_key.aes_key_hex).to eq(new_key)
      expect(gw_hw_key.previous_aes_key_hex).to eq(gw_key_hex)
    end

    it "raises when device not found" do
      expect {
        described_class.rotate("NONEXISTENT-DID")
      }.to raise_error(RuntimeError, /не знайдено/)
    end
  end

  # =========================================================================
  # HKDF DERIVATION DETAILS
  # =========================================================================
  describe ".derive_device_key with HKDF" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("test-master-key-for-hkdf-derive!")
    end

    it "uses SHA256 as hash algorithm" do
      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything,
        hash_including(hash: "SHA256")
      ).and_call_original

      described_class.derive_device_key("TEST-DEVICE-001")
    end

    it "uses HKDF_INFO constant as info parameter" do
      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything,
        hash_including(info: "silken-aes-256-device-key")
      ).and_call_original

      described_class.derive_device_key("TEST-DEVICE-002")
    end

    # 🔴 [TEST.12, вісь ПРОВЕНАНСУ] Решта трьох info-рядків доти не мали ЖОДНОГО
    # літерального піна: їхні оракули будувались із тієї самої константи, яку мали б
    # стерегти (`info: described_class::IOTEX_HKDF_INFO`, `eq(derive_lora_key(...))`),
    # тобто приклад був тотожністю. Зміна константи на `…-v2` лишала сюїту зеленою,
    # а деривація віддавала інший ключ, ніж прошито в залізі й зареєстровано в
    # W3bstream — тобто мовчазна відмова атестацій і закритий мінт-гейт.
    # Форму взято в сусіда вище: рядок ЛІТЕРАЛОМ, бо саме рядок є контрактом із
    # прошитим пристроєм. Дім значень — `03_05 §3`.
    it "прибиває три інші HKDF-info ЛІТЕРАЛАМИ, бо контракт із залізом — сам рядок" do
      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything, hash_including(info: "silken-aes-128-lora-key")
      ).and_call_original
      described_class.derive_lora_key("TEST-DEVICE-004")

      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything, hash_including(info: "silken-aes-128-broadcast-key")
      ).and_call_original
      described_class.derive_broadcast_key(42)

      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything, hash_including(info: "silken-ed25519-iotex-v1")
      ).and_call_original
      described_class.derive_iotex_seed("TEST-DEVICE-004")
    end

    it "returns exactly 64 hex characters (32 bytes)" do
      key = described_class.derive_device_key("TEST-DEVICE-003")
      expect(key.length).to eq(64)
      expect(key).to match(/\A[0-9A-F]+\z/)
    end

    it "uses device_uid as HKDF salt" do
      expect(OpenSSL::KDF).to receive(:hkdf).with(
        anything,
        hash_including(salt: "UNIQUE-UID-123")
      ).and_call_original

      described_class.derive_device_key("UNIQUE-UID-123")
    end
  end

  # =========================================================================
  # PROVISION CONFLICT
  # =========================================================================
  describe ".provision idempotency" do
    it "raises on duplicate provision for same device" do
      described_class.provision(tree)

      expect {
        described_class.provision(tree)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # [FW.17] Legacy "sys/key_update" видалено: він слав КЛЮЧ ефіром (проти
  # принципу §3.8), не мав firmware-споживача і викликав ActuatorCommandWorker
  # з чужою арністю. Gateway-ротація тепер БД-only (доставка = re-provision).
  describe "key update downlink (post-FW.17)" do
    it "gateway rotation enqueues no downlink at all" do
      allow(ActuatorCommandWorker).to receive(:perform_async)
      gateway = create(:gateway, :online, cluster: cluster, ip_address: "192.168.1.1")
      HardwareKey.create!(device_uid: gateway.uid, aes_key_hex: SecureRandom.hex(32).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

      new_key = described_class.rotate(gateway.uid)

      expect(new_key).to be_present
      expect(ActuatorCommandWorker).not_to have_received(:perform_async)
      expect(KeyRotationDownlinkWorker).not_to have_received(:perform_async)
    end

    it "tree rotation enqueues only the 0x9E ratchet command (key never airborne)" do
      open_ratchet_gate!
      tree_device = create(:tree, cluster: cluster)
      # Post-ARCH.42: Tree-shaped HardwareKey = 32 hex (16-byte AES-128 LoRa key).
      HardwareKey.create!(device_uid: tree_device.did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

      new_key = described_class.rotate(tree_device.did)

      expect(new_key).to be_present
      expect(KeyRotationDownlinkWorker).to have_received(:perform_async).with(tree_device.did, 1)
    end
  end

  # [SEC.3 DI] Явний master_key: живить HKDF замість ENV — інакше non-ENV
  # adapter (Bitwarden/HSM) був би мертвим кодом.
  describe "master_key DI [SEC.3]" do
    let(:di_key) { "di-alive-proof-master-key-distinct" }

    it "derive_device_key honours the param (independent HKDF oracle)" do
      via_param = described_class.derive_device_key(tree.did, master_key: di_key)
      expect(via_param).not_to eq(described_class.derive_device_key(tree.did))

      oracle = OpenSSL::KDF.hkdf(
        di_key, salt: tree.did, info: described_class::COAP_HKDF_INFO,
        length: described_class::COAP_KEY_SIZE_BYTES, hash: "SHA256"
      ).unpack1("H*").upcase
      expect(via_param).to eq(oracle)
    end

    it "provision threads the param into both the AES key and Lorenz K_seed" do
      described_class.provision(tree, master_key: di_key)
      row = HardwareKey.find_by!(device_uid: tree.did)

      expect(row.aes_key_hex).to eq(described_class.derive_lora_key(tree.did, master_key: di_key))
      expect(row.aes_key_hex).not_to eq(described_class.derive_lora_key(tree.did))
      expect(row.lorenz_seed_hex).to eq(SilkenNet::SeedDerivation.derive_seed(tree.did, master_key: di_key))
      expect(row.lorenz_seed_hex).not_to eq(SilkenNet::SeedDerivation.derive_seed(tree.did))
    end
  end
end
