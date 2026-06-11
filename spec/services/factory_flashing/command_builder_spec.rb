# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::CommandBuilder do
  let(:tree)    { create(:tree) }
  let(:gateway) { create(:gateway) }

  # Deterministic fixtures so the golden-vector assertions stay stable.
  let(:aes_lora_hex) { "0123456789ABCDEF0123456789ABCDEF" }                                # 16 bytes
  let(:aes_coap_hex) { "F" * 64 }                                                          # 32 bytes
  let(:k_seed_hex)   { "00112233445566778899AABBCCDDEEFF" + "FFEEDDCCBBAA99887766554433221100" }
  let(:k_ota_hex)    { "A1B2C3D4E5F60718293A4B5C6D7E8F90" + "0F1E2D3C4B5A69788796A5B4C3D2E1F0" }

  describe "Гілка A — Tree" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: tree,
        aes_key_hex: aes_lora_hex,
        lorenz_seed_hex: k_seed_hex,
        ota_hmac_hex: k_ota_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }

    it "opens SWD, writes KEYL+AES16, LSED+seed32, KOTA+k_ota32 (FW.23), then sets RDP" do
      expect(commands).to eq([
        "STM32_Programmer_CLI -c port=SWD reset=HWrst",
        # KEYL magic + 4 AES words at 0x0803E000..0x0803E010
        "STM32_Programmer_CLI -w32 0x0803E000 0x4B45594C",
        "STM32_Programmer_CLI -w32 0x0803E004 0x01234567",
        "STM32_Programmer_CLI -w32 0x0803E008 0x89ABCDEF",
        "STM32_Programmer_CLI -w32 0x0803E00C 0x01234567",
        "STM32_Programmer_CLI -w32 0x0803E010 0x89ABCDEF",
        # LSED magic + 8 K_seed words at 0x0803E014..0x0803E030
        "STM32_Programmer_CLI -w32 0x0803E014 0x4C534544",
        "STM32_Programmer_CLI -w32 0x0803E018 0x00112233",
        "STM32_Programmer_CLI -w32 0x0803E01C 0x44556677",
        "STM32_Programmer_CLI -w32 0x0803E020 0x8899AABB",
        "STM32_Programmer_CLI -w32 0x0803E024 0xCCDDEEFF",
        "STM32_Programmer_CLI -w32 0x0803E028 0xFFEEDDCC",
        "STM32_Programmer_CLI -w32 0x0803E02C 0xBBAA9988",
        "STM32_Programmer_CLI -w32 0x0803E030 0x77665544",
        "STM32_Programmer_CLI -w32 0x0803E034 0x33221100",
        # [FW.23] KOTA magic + 8 K_ota words — окремий сектор 0x0803D000;
        # розкладка дзеркалить Load_Ota_Hmac_Key (firmware/soldier/main.c)
        "STM32_Programmer_CLI -w32 0x0803D000 0x4B4F5441",
        "STM32_Programmer_CLI -w32 0x0803D004 0xA1B2C3D4",
        "STM32_Programmer_CLI -w32 0x0803D008 0xE5F60718",
        "STM32_Programmer_CLI -w32 0x0803D00C 0x293A4B5C",
        "STM32_Programmer_CLI -w32 0x0803D010 0x6D7E8F90",
        "STM32_Programmer_CLI -w32 0x0803D014 0x0F1E2D3C",
        "STM32_Programmer_CLI -w32 0x0803D018 0x4B5A6978",
        "STM32_Programmer_CLI -w32 0x0803D01C 0x8796A5B4",
        "STM32_Programmer_CLI -w32 0x0803D020 0xC3D2E1F0",
        "STM32_Programmer_CLI -ob RDP=1",
        "STM32_Programmer_CLI -c port=SWD --quietMode"
      ])
    end

    it "refuses a Tree without ota_hmac_hex — інакше OTA вічно fail-closed (FW.23)" do
      expect {
        described_class.new(
          session: session,
          device: tree,
          aes_key_hex: aes_lora_hex,
          lorenz_seed_hex: k_seed_hex
        )
      }.to raise_error(ArgumentError, /ota_hmac_hex/)
    end

    it "honours rdp_level=2 (irreversible) in emitted RDP command" do
      session.rdp_level = 2
      expect(commands).to include("STM32_Programmer_CLI -ob RDP=2")
    end
  end

  describe "Гілка A — Gateway" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: gateway,
        aes_key_hex: aes_coap_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }

    it "writes KEYC magic + 8 AES-256 words at FLASH_COAP_KEY_ADDR" do
      expect(commands.first).to eq("STM32_Programmer_CLI -c port=SWD reset=HWrst")
      expect(commands).to include("STM32_Programmer_CLI -w32 0x0803E040 0x4B455943")
      expect(commands.count { |c| c.include?("-w32") }).to eq(9) # magic + 8 key words
      expect(commands.last(2).first).to eq("STM32_Programmer_CLI -ob RDP=1")
    end

    it "does NOT write the Lorenz K_seed slot (gateway has no Lorenz attractor)" do
      expect(commands).to all(satisfy { |c| !c.include?("0x4C534544") })
    end

    it "skips the EDSK slot when ed25519_seed_hex is absent (Queen стає L0)" do
      expect(commands).to all(satisfy { |c| !c.include?("0x4544534B") })
    end
  end

  # [L1 QATT] Голос Королеви — сім'я Ed25519 у Protected Flash (05_02 ladder L1)
  describe "Гілка A — Gateway з ed25519_seed_hex" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: gateway,
        aes_key_hex: aes_coap_hex,
        ed25519_seed_hex: ed25519_seed_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }
    let(:ed25519_seed_hex) { "53494C4B454E2D4E45542D4C312D514154542D474F4C44454E2D534545442121" }

    it "writes EDSK magic + 8 seed words right after the KEYC block" do
      expect(commands).to include("STM32_Programmer_CLI -w32 0x0803E064 0x4544534B")
      # KEYC (9) + EDSK (9) word-команд
      expect(commands.count { |c| c.include?("-w32") }).to eq(18)
      # перше seed-слово BE — firmware розгортає word→BE-байти (FW.30-конвенція)
      expect(commands).to include("STM32_Programmer_CLI -w32 0x0803E068 0x53494C4B")
    end

    it "rejects ed25519_seed_hex on a Tree (Gateway-only slot)" do
      expect {
        described_class.new(
          session: session, device: tree,
          aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex,
          ed25519_seed_hex: ed25519_seed_hex
        )
      }.to raise_error(ArgumentError, /Gateway-only/)
    end

    it "rejects a non-64-hex seed" do
      expect {
        described_class.new(
          session: session, device: gateway,
          aes_key_hex: aes_coap_hex, ed25519_seed_hex: "BEEF"
        )
      }.to raise_error(ArgumentError, /64 hex/)
    end
  end

  describe "Гілка B" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: tree,
        aes_key_hex: aes_lora_hex,
        lorenz_seed_hex: k_seed_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, :gilka_b, rdp_level: 1) }

    it "skips SWD key writes — only firmware connect + RDP lock + disconnect" do
      expect(commands).to eq([
        "STM32_Programmer_CLI -c port=SWD reset=HWrst",
        "STM32_Programmer_CLI -ob RDP=1",
        "STM32_Programmer_CLI -c port=SWD --quietMode"
      ])
    end
  end

  describe "validation" do
    let(:session) { build(:provisioning_session, gilka: "A") }

    it "rejects AES key that is not 32 or 64 hex chars" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: "ABC", lorenz_seed_hex: k_seed_hex)
      }.to raise_error(ArgumentError, /32 or 64 hex/)
    end

    it "rejects non-hex AES key" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: "Z" * 32, lorenz_seed_hex: k_seed_hex)
      }.to raise_error(ArgumentError, /hexadecimal/)
    end

    it "Tree requires K_seed of 64 hex" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: "00")
      }.to raise_error(ArgumentError, /lorenz_seed_hex/)
    end

    it "Tree with 64-hex AES (wrong size for LoRa) raises in #commands" do
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_coap_hex, lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /AES-128/)
    end

    it "Gateway with 32-hex AES raises in #commands" do
      builder = described_class.new(session: session, device: gateway, aes_key_hex: aes_lora_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /AES-256/)
    end

    it "rejects non-hex lorenz_seed_hex (64 chars but with Z's)" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: "Z" * 64)
      }.to raise_error(ArgumentError, /lorenz_seed_hex must be hexadecimal/)
    end

    it "raises on unknown gilka value at #commands" do
      session.gilka = "C"
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /Unknown gilka/)
    end
  end
end
