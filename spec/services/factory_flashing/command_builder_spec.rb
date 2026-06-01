# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::CommandBuilder do
  let(:tree)    { create(:tree) }
  let(:gateway) { create(:gateway) }

  # Deterministic fixtures so the golden-vector assertions stay stable.
  let(:aes_lora_hex) { "0123456789ABCDEF0123456789ABCDEF" }                                # 16 bytes
  let(:aes_coap_hex) { "F" * 64 }                                                          # 32 bytes
  let(:k_seed_hex)   { "00112233445566778899AABBCCDDEEFF" + "FFEEDDCCBBAA99887766554433221100" }

  describe "Гілка A — Tree" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: tree,
        aes_key_hex: aes_lora_hex,
        lorenz_seed_hex: k_seed_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }

    it "opens SWD, writes KEYL+AES16 at 0x0803E000, LSED+seed32 at 0x0803E014, then sets RDP" do
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
        "STM32_Programmer_CLI -ob RDP=1",
        "STM32_Programmer_CLI -c port=SWD --quietMode"
      ])
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
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_coap_hex, lorenz_seed_hex: k_seed_hex)
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
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /Unknown gilka/)
    end
  end
end
