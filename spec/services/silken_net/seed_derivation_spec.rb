# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::SeedDerivation do
  let(:master_key) { "silken-net-test-master-key-32b!!" }
  let(:device_uid) { "SNET-AC0001AB" }

  describe ".derive_seed" do
    context "with PROVISIONING_MASTER_KEY (HKDF mode)" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(master_key)
      end

      it "returns a 64-char uppercase hex string (32 bytes)" do
        seed = described_class.derive_seed(device_uid)
        expect(seed).to be_a(String)
        expect(seed.length).to eq(64)
        expect(seed).to match(/\A[0-9A-F]{64}\z/)
      end

      it "is deterministic — same inputs produce identical K_seed" do
        a = described_class.derive_seed(device_uid)
        b = described_class.derive_seed(device_uid)
        expect(a).to eq(b)
      end

      it "produces different K_seed for different device_uid" do
        a = described_class.derive_seed("SNET-AAAAAAAA")
        b = described_class.derive_seed("SNET-BBBBBBBB")
        expect(a).not_to eq(b)
      end

      it "produces different K_seed when master key changes" do
        first = described_class.derive_seed(device_uid)
        allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("different-master-key-32-bytes!!!!")
        second = described_class.derive_seed(device_uid)
        expect(first).not_to eq(second)
      end

      it "is independent from HardwareKeyService AES key derivation (domain separation)" do
        seed = described_class.derive_seed(device_uid)
        aes  = HardwareKeyService.derive_device_key(device_uid)
        expect(seed).not_to eq(aes)
      end
    end

    context "without PROVISIONING_MASTER_KEY [SEC.11 hard cutover]" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)
      end

      it "raises SecurityError — no SecureRandom fallback" do
        expect {
          described_class.derive_seed(device_uid)
        }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
      end
    end

    # [SEC.3 DI] Явний master_key: живить HKDF замість ENV.
    context "with explicit master_key: param [SEC.3 DI]" do
      it "derives from the param, not ENV" do
        via_param = described_class.derive_seed(device_uid, master_key: "di-alive-proof-master-key-distinct")
        expect(via_param).to match(/\A[0-9A-F]{64}\z/)
        expect(via_param).not_to eq(described_class.derive_seed(device_uid))
      end
    end
  end

  describe ".initial_state" do
    let(:seed_bytes) { ("\x00".b * 32) }

    it "returns three Floats in [-1, +1]" do
      x0, y0, z0 = described_class.initial_state(seed_bytes, 20_210)
      expect(x0).to be_a(Float)
      expect(y0).to be_a(Float)
      expect(z0).to be_a(Float)
      expect([ x0, y0, z0 ]).to all(be_finite.and(be_between(-1.0, 1.0)))
    end

    it "is deterministic for the same (seed, epoch_day)" do
      a = described_class.initial_state(seed_bytes, 20_210)
      b = described_class.initial_state(seed_bytes, 20_210)
      expect(a).to eq(b)
    end

    it "rotates daily — different epoch_day → different (x0, y0, z0)" do
      a = described_class.initial_state(seed_bytes, 20_210)
      b = described_class.initial_state(seed_bytes, 20_211)
      expect(a).not_to eq(b)
    end

    it "depends on K_seed — different bytes → different coords" do
      other_bytes = ("\xFF".b * 32)
      a = described_class.initial_state(seed_bytes, 20_210)
      b = described_class.initial_state(other_bytes, 20_210)
      expect(a).not_to eq(b)
    end

    it "raises ArgumentError when seed_bytes is not 32 bytes" do
      expect {
        described_class.initial_state("\x00".b * 16, 0)
      }.to raise_error(ArgumentError, /32 bytes/)
    end

    it "uses today's UTC epoch_day by default" do
      expected_day = (Time.now.utc.to_i / 86_400)
      explicit = described_class.initial_state(seed_bytes, expected_day)
      implicit = described_class.initial_state(seed_bytes)
      expect(implicit).to eq(explicit)
    end

    # 🔴 [TEST.12, вісь ПРОВЕНАНСУ] Усі приклади вище РЕЛЯЦІЙНІ: вони звіряють виклик
    # із ще одним викликом того самого методу (детермінізм, ротація, залежність від
    # сіда) або перевіряють лише тип і діапазон. Тобто оракул позичений у коду, який
    # перевіряється, і приклад є тотожністю. Виміряно мутацією: перестановка зрізів
    # x0↔y0 виживає ВСЮ цю спеку і ще 245 прикладів суміжного периметра
    # (`hardware_key_service`, `factory_flashing`, `provisioning`) — бо кожна з
    # перевірених властивостей інваріантна під будь-якою перестановкою трьох зрізів.
    #
    # Ціна мовчазної зміни розкладки не косметична: цей стан годує Lorenz-траєкторію,
    # а backend мусить бути БІТОВО тотожний firmware-mruby (FW.7). Свап на одному боці
    # розводить DCI-звірку без жодного червоного тесту.
    #
    # ⚠️ Межа цих двох прикладів названа чесно: вони МОРОЗЯТЬ чинну розкладку як
    # контракт (під неї вже прошито залізо), а не доводять її правильність.
    describe "золотий вектор — розкладка дайджесту заморожена" do
      let(:frozen_seed) { ("\x00".."\x1f").to_a.join.b }

      it "віддає ті самі координати для фіксованої пари (seed, epoch_day)" do
        expect(described_class.initial_state(frozen_seed, 20_000)).to eq(
          [ -0.7456425164358368, 0.46030256489974186, -0.8144958023098249 ]
        )
      end

      # Оракул НЕЗАЛЕЖНИЙ: HMAC рахується прямо OpenSSL за оголошеною специфікацією
      # (`"init|"` + big-endian epoch), а не через `initial_state`. Тож приклад пінить
      # саме ПОЗИЦІЇ зрізів і лишається чинним, навіть якщо зміниться `signed_unit_float`.
      it "бере x0/y0/z0 саме з байтів 0/8/16, а не з іншої перестановки" do
        digest = OpenSSL::HMAC.digest("SHA256", frozen_seed, "init|".b + [ 20_000 ].pack("Q>"))

        expect(described_class.initial_state(frozen_seed, 20_000)).to eq(
          [
            described_class.signed_unit_float(digest[0, 8]),
            described_class.signed_unit_float(digest[8, 8]),
            described_class.signed_unit_float(digest[16, 8])
          ]
        )
      end
    end
  end

  describe ".signed_unit_float" do
    it "maps zero bytes near -1.0" do
      v = described_class.signed_unit_float("\x00".b * 8)
      expect(v).to be_within(1e-15).of(-1.0)
    end

    it "maps all-FF bytes to +1.0" do
      v = described_class.signed_unit_float("\xFF".b * 8)
      expect(v).to eq(1.0)
    end

    it "maps midpoint bytes near 0.0" do
      midpoint = [ 0x80, 0, 0, 0, 0, 0, 0, 0 ].pack("C*")
      v = described_class.signed_unit_float(midpoint)
      expect(v).to be_within(1e-9).of(0.0)
    end
  end

  describe ".current_epoch_day" do
    it "returns Time#to_i / 86_400 for the supplied UTC time" do
      t = Time.utc(2026, 5, 2, 12, 34, 56)
      expect(described_class.current_epoch_day(t)).to eq(t.to_i / 86_400)
    end
  end

  describe ".initial_state argument validation" do
    it "raises ArgumentError when seed_bytes is nil" do
      expect { described_class.initial_state(nil) }
        .to raise_error(ArgumentError, /seed_bytes must be 32 bytes/)
    end
  end
end
