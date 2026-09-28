# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # [FW.2 (в)] Cluster control-plane ключ (KEYB): Tree → KEYB-слот, Gateway → її KEYL
  let(:bcast_hex)    { "B0B1B2B3C0C1C2C3D0D1D2D3E0E1E2E3" }                                # 16 bytes

  describe "Гілка A — Tree" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: tree,
        aes_key_hex: aes_lora_hex,
        lorenz_seed_hex: k_seed_hex,
        ota_hmac_hex: k_ota_hex,
        bcast_key_hex: bcast_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }

    # Golden-транскрипт атомарний (один eq-масив = повний фабричний контракт) —
    # різати на шматки шкідливо для читабельності діфа при зміні layout'у.
    it "reads the UID, erases the key pages, writes KEYL·LSED and KOTA·KEYB as whole doublewords, then IWDG and RDP" do
      expect(commands).to eq([
        # [FW.54] SWD-read кремнієвого паспорта — wrong-board guard (Session)
        "STM32_Programmer_CLI -c port=SWD mode=UR -r32 0x1FFF7590 12 -r32 0x0803E000 4",
        # `-w32` не стирає — re-flash без цього рядка впав би на першому ж записі
        "STM32_Programmer_CLI -c port=SWD mode=UR -e 124 125",
        # стор. 124: KEYL magic + 4 AES words, LSED magic + 8 K_seed words —
        # 14 слів = рівно 7 doubleword'ів
        "STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E000 " \
        "0x4B45594C 0x01234567 0x89ABCDEF 0x01234567 0x89ABCDEF " \
        "0x4C534544 0x00112233 0x44556677 0x8899AABB 0xCCDDEEFF 0xFFEEDDCC 0xBBAA9988 0x77665544 0x33221100",
        # стор. 125: [FW.23] KOTA magic + 8 K_ota words (розкладка дзеркалить
        # Load_Ota_Hmac_Key) + стерте слово до кінця doubleword'а; [FW.2 (в)]
        # KEYB magic + 4 broadcast words зі старту +40 + ще одне стерте слово
        "STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E800 " \
        "0x4B4F5441 0xA1B2C3D4 0xE5F60718 0x293A4B5C 0x6D7E8F90 0x0F1E2D3C 0x4B5A6978 0x8796A5B4 0xC3D2E1F0 0xFFFFFFFF " \
        "0x4B455942 0xB0B1B2B3 0xC0C1C2C3 0xD0D1D2D3 0xE0E1E2E3 0xFFFFFFFF",
        # [SEC.15] пес заморожений у STOP2/STANDBY — ДО RDP (03_01 §1.10)
        "STM32_Programmer_CLI -c port=SWD mode=UR -ob IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0",
        "STM32_Programmer_CLI -c port=SWD mode=UR -ob RDP=0xBB"
      ])
    end

    it "refuses Gilka A without bcast_key_hex — Солдат CCM-ери глухне до downlink'а (FW.2 (в))" do
      expect {
        described_class.new(
          session: session,
          device: tree,
          aes_key_hex: aes_lora_hex,
          lorenz_seed_hex: k_seed_hex,
          ota_hmac_hex: k_ota_hex
        )
      }.to raise_error(ArgumentError, /bcast_key_hex/)
    end

    it "refuses a Tree without ota_hmac_hex — інакше OTA вічно fail-closed (FW.23)" do
      expect {
        described_class.new(
          session: session,
          device: tree,
          aes_key_hex: aes_lora_hex,
          lorenz_seed_hex: k_seed_hex,
          bcast_key_hex: bcast_hex
        )
      }.to raise_error(ArgumentError, /ota_hmac_hex/)
    end

    it "emits rdp_level=0 as the L0 byte — the number 0 would lock L1" do
      session.rdp_level = 0
      expect(commands.last).to eq("STM32_Programmer_CLI -c port=SWD mode=UR -ob RDP=0xAA")
    end

    it "maps every RDP level the session accepts (a level without a byte fails here, not at the factory)" do
      expect(described_class::RDP_OPTION_BYTE.keys).to match_array(ProvisioningSession::RDP_LEVELS)
    end
  end

  describe "Гілка A — Gateway" do
    subject(:commands) do
      described_class.new(
        session: session,
        device: gateway,
        aes_key_hex: aes_coap_hex,
        bcast_key_hex: bcast_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }

    it "writes KEYC magic + 8 AES-256 words at FLASH_COAP_KEY_ADDR" do
      expect(commands.first).to eq("STM32_Programmer_CLI -c port=SWD mode=UR -r32 0x1FFF7590 12 -r32 0x0803E000 4")
      expect(flash_image(commands)[0x0803E040]).to eq("0x4B455943")
      # KEYL(broadcast, 5) + стерте слово · KEYC(9) + стерте слово — FW.2 (в)
      expect(flash_image(commands).keys).to eq((0x0803E000...0x0803E018).step(4).to_a +
                                               (0x0803E040...0x0803E068).step(4).to_a)
      expect(commands.last).to eq("STM32_Programmer_CLI -c port=SWD mode=UR -ob RDP=0xBB")
    end

    it "writes KEYL slot with the BROADCAST value — фікс фабричної цегли (FW.2 (в))" do
      # До 2026-07-03 Gateway KEYL не писався взагалі → Queen Load_AES_Key()
      # без magic = Error_Handler → reset-петля на першому boot.
      expect(flash_image(commands).values_at(0x0803E000, 0x0803E004)).to eq(%w[0x4B45594C 0xB0B1B2B3])
    end

    it "refuses Gilka A Gateway without bcast_key_hex — інакше Королева цеглиться на boot" do
      expect {
        described_class.new(session: session, device: gateway, aes_key_hex: aes_coap_hex)
      }.to raise_error(ArgumentError, /bcast_key_hex/)
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
        ed25519_seed_hex: ed25519_seed_hex,
        bcast_key_hex: bcast_hex
      ).commands
    end

    let(:session) { build(:provisioning_session, gilka: "A", rdp_level: 1) }
    let(:ed25519_seed_hex) { "53494C4B454E2D4E45542D4C312D514154542D474F4C44454E2D534545442121" }

    it "writes EDSK magic + 8 seed words right after the KEYC block" do
      image = flash_image(commands)
      expect(image[0x0803E064]).to eq("0x4544534B")
      # KEYL-broadcast (5) + стерте слово + KEYC (9) + EDSK (9): KEYC·EDSK
      # закінчуються рівно на межі doubleword'а — FW.2 (в)
      expect(image.size).to eq(24)
      # перше seed-слово BE — firmware розгортає word→BE-байти (FW.30-конвенція)
      expect(image[0x0803E068]).to eq("0x53494C4B")
    end

    it "rejects ed25519_seed_hex on a Tree (Gateway-only slot)" do
      expect {
        described_class.new(
          session: session, device: tree,
          aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex,
          ed25519_seed_hex: ed25519_seed_hex, bcast_key_hex: bcast_hex
        )
      }.to raise_error(ArgumentError, /Gateway-only/)
    end

    it "rejects a non-64-hex seed" do
      expect {
        described_class.new(
          session: session, device: gateway,
          aes_key_hex: aes_coap_hex, ed25519_seed_hex: "BEEF",
          bcast_key_hex: bcast_hex
        )
      }.to raise_error(ArgumentError, /64 hex/)
    end

    it "rejects a 64-char but non-hex seed" do
      expect {
        described_class.new(
          session: session, device: gateway,
          aes_key_hex: aes_coap_hex, ed25519_seed_hex: "Z" * 64,
          bcast_key_hex: bcast_hex
        )
      }.to raise_error(ArgumentError, /hexadecimal/)
    end
  end

  # [SE050-MIGRATION, ⚖️ делеговано 2026-09-27] Гілка B = Гілка A + identity-chip:
  # кожен Protected-Flash-ключ має MCU-споживача, тож SWD-транскрипт однаковий, а
  # SE-кроки (ідентичність) емітить SecureElementProvisioner окремо. Доти Гілка B
  # не писала жодного ключа — KEYL-less Солдат цеглився на першому boot.
  describe "Гілка B" do
    def commands_for(gilka, device:, aes_key_hex:, **keys)
      described_class.new(session: build(:provisioning_session, gilka: gilka, rdp_level: 1),
                          device: device, aes_key_hex: aes_key_hex, bcast_key_hex: bcast_hex, **keys).commands
    end

    it "writes the Tree the same Protected-Flash key set as Гілка A (KEYL · LSED · KOTA · KEYB)" do
      keys = { lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex }
      b = commands_for("B", device: tree, aes_key_hex: aes_lora_hex, **keys)

      expect(b).to eq(commands_for("A", device: tree, aes_key_hex: aes_lora_hex, **keys))
      expect(flash_image(b)[0x0803E000]).to eq("0x4B45594C") # KEYL magic
    end

    it "writes a Queen her KEYC too — SE-less, Гілка B is Гілка A for her" do
      b = commands_for("B", device: gateway, aes_key_hex: aes_coap_hex)

      expect(b).to eq(commands_for("A", device: gateway, aes_key_hex: aes_coap_hex))
      expect(flash_image(b)[0x0803E040]).to eq("0x4B455943") # KEYC magic
    end
  end

  # [SEC.15] LSI-пес лічить і в STOP2 (max ~32.7 с), тож без `IWDG_STOP=0` Солдат
  # ресетиться посеред кожного багатогодинного сну. Порядок несучий: на L2 option bytes
  # стають read-only, і незаморожений пес лишився б таким назавжди (03_05 §3.3).
  describe "IWDG-заморозка перед RDP" do
    let(:iwdg) { "STM32_Programmer_CLI -c port=SWD mode=UR -ob IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0" }

    def transcript(device:, rdp_level:, **keys)
      described_class.new(session: build(:provisioning_session, gilka: "A", rdp_level: rdp_level),
                          device: device, bcast_key_hex: bcast_hex, **keys).commands
    end

    [ 0, 1 ].each do |level|
      it "Солдат на L#{level}: IWDG пишеться рівно раз і ДО RDP" do
        cmds = transcript(device: tree, rdp_level: level, aes_key_hex: aes_lora_hex,
                          lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex)

        expect(cmds.count(iwdg)).to eq(1)
        expect(cmds.index(iwdg)).to be < cmds.index { |c| c.include?("-ob RDP=") }
      end
    end

    # Королева в STOP2 не входить, тож STOP/STDBY-біти для неї інертні, а `IWDG_SW=1`
    # збігається з її `MX_IWDG_Init` — той самий крок коректний для обох типів.
    it "Королева теж: IWDG ДО RDP" do
      cmds = transcript(device: gateway, rdp_level: 1, aes_key_hex: aes_coap_hex)

      expect(cmds.index(iwdg)).to be < cmds.index { |c| c.include?("-ob RDP=") }
    end
  end

  # [SEC.3] Форма транскрипту — під CLI і кремній WL, а не під уявну сесію: кожен
  # рядок є окремим процесом (з'єднання між процесами не живе), а Flash приймає
  # лише цілий doubleword по стертому (`-w32` сам не стирає). Доти вирівняли лише
  # межу KOTA|KEYB — магія зі словом ключа й межа KEYL|LSED ділили doubleword.
  describe "форма запису Flash WL" do
    let(:voice_seed) { "53494C4B454E2D4E45542D4C312D514154542D474F4C44454E2D534545442121" }
    let(:transcripts) do
      transcript_for = lambda do |device, **keys|
        described_class.new(session: build(:provisioning_session, gilka: "A", rdp_level: 1),
                            device: device, bcast_key_hex: bcast_hex, **keys).commands
      end
      {
        tree:        transcript_for.call(tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex),
        queen:       transcript_for.call(gateway, aes_key_hex: aes_coap_hex),
        queen_voice: transcript_for.call(gateway, aes_key_hex: aes_coap_hex, ed25519_seed_hex: voice_seed)
      }
    end

    it "кожен рядок під'єднується сам — з'єднання між процесами CLI не живе" do
      transcripts.each_value do |cmds|
        expect(cmds).to all(start_with("STM32_Programmer_CLI -c port=SWD mode=UR "))
      end
    end

    it "кожен зачеплений doubleword пишеться рівно раз і цілим" do
      transcripts.each_value do |cmds|
        writes = cmds.grep(/ -w32 /).map { |c| c.split(" -w32 ", 2).last.split }
        addrs  = writes.flat_map { |addr, *words| words.each_index.map { |i| Integer(addr, 16) + (4 * i) } }

        expect(addrs).to eq(addrs.uniq)
        expect(writes).to all(satisfy { |addr, *words| (Integer(addr, 16) % 8).zero? && words.size.even? })
      end
    end

    # Формат живе тут, редакція — в Executor (друк dry-run і персистоване повідомлення
    # помилки): пін звʼязує обидва, тож зміна форми `-w32` не вимикає редакцію мовчки.
    it "Executor.redact ховає кожне слово кожного ключа з кожного рядка" do
      key_words = [ aes_lora_hex, k_seed_hex, k_ota_hex, bcast_hex, voice_seed ].flat_map { |hex| hex.scan(/.{8}/) }
      transcripts.each_value do |cmds|
        redacted = cmds.map { |c| FactoryFlashing::Executor.redact(c) }.join("\n").upcase
        expect(key_words.select { |w| redacted.include?(w) }).to be_empty
      end
    end

    it "стирає ДО запису рівно сторінки ключів — Королевину 125 (рантайм-OTA-SHA, FW.52) ніколи" do
      expect(transcripts[:tree].grep(/ -e /)).to eq([ "STM32_Programmer_CLI -c port=SWD mode=UR -e 124 125" ])
      expect(transcripts.values_at(:queen, :queen_voice).map { |c| c.grep(/ -e /) })
        .to all(eq([ "STM32_Programmer_CLI -c port=SWD mode=UR -e 124" ]))
      transcripts.each_value do |cmds|
        expect(cmds.index { |c| c.include?(" -e ") }).to be < cmds.index { |c| c.include?(" -w32 ") }
      end
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
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: "00", bcast_key_hex: bcast_hex)
      }.to raise_error(ArgumentError, /lorenz_seed_hex/)
    end

    it "Tree with 64-hex AES (wrong size for LoRa) raises in #commands" do
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_coap_hex, lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex, bcast_key_hex: bcast_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /AES-128/)
    end

    it "Gateway with 32-hex AES raises in #commands" do
      builder = described_class.new(session: session, device: gateway, aes_key_hex: aes_lora_hex, bcast_key_hex: bcast_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /AES-256/)
    end

    it "rejects non-hex lorenz_seed_hex (64 chars but with Z's)" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: "Z" * 64, bcast_key_hex: bcast_hex)
      }.to raise_error(ArgumentError, /lorenz_seed_hex must be hexadecimal/)
    end

    it "rejects non-hex ota_hmac_hex (64 chars but with Z's)" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex,
                            lorenz_seed_hex: k_seed_hex, ota_hmac_hex: "Z" * 64, bcast_key_hex: bcast_hex)
      }.to raise_error(ArgumentError, /ota_hmac_hex must be hexadecimal/)
    end

    it "rejects non-hex bcast_key_hex (32 chars but with Z's) — FW.2 (в)" do
      expect {
        described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex,
                            lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex, bcast_key_hex: "Z" * 32)
      }.to raise_error(ArgumentError, /bcast_key_hex must be hexadecimal/)
    end

    it "requires bcast_key_hex on Gilka B too — KEYB lives in MCU Flash on both branches" do
      gilka_b = build(:provisioning_session, :gilka_b)
      expect {
        described_class.new(session: gilka_b, device: tree, aes_key_hex: aes_lora_hex,
                            lorenz_seed_hex: k_seed_hex, ota_hmac_hex: k_ota_hex)
      }.to raise_error(ArgumentError, /bcast_key_hex is required/)
    end

    it "raises on unknown gilka value at #commands" do
      session.gilka = "C"
      builder = described_class.new(session: session, device: tree, aes_key_hex: aes_lora_hex, lorenz_seed_hex: k_seed_hex,
                                    ota_hmac_hex: k_ota_hex, bcast_key_hex: bcast_hex)
      expect { builder.commands }.to raise_error(ArgumentError, /Unknown gilka/)
    end
  end
end
