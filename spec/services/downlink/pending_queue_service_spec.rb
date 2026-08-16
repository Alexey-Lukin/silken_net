# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Downlink::PendingQueueService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster, state: :idle) }
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before { Rails.cache.clear }

  def decrypt_inner(envelope, key: key_record.binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc").decrypt
    cipher.key = key
    cipher.iv = envelope.byteslice(0, 16)
    cipher.padding = 0
    plain = cipher.update(envelope.byteslice(16, envelope.bytesize)) + cipher.final
    expect(plain.getbyte(0)).to eq(0x9C) # time-sync конверт завжди перший
    plain.byteslice(5, plain.bytesize)
  end

  def poll(query = {})
    described_class.poll_reply(gateway: gateway, query: query)
  end

  describe "порожня черга" do
    it "віддає time-only конверт (32 Б): кожен poll = RTC-sync Королеви" do
      envelope = poll

      expect(envelope.bytesize).to eq(32)
      expect(decrypt_inner(envelope).bytes).to all(eq(0))
    end

    it "без KEYC → nil (CoapGate відповість 4.04, Queen не почне decrypt)" do
      key_record.destroy!

      expect(poll).to be_nil
    end

    it "шифрує СТАРИМ ключем у Dual-Key Grace (Королева ще не підтвердила ротацію)" do
      key_record.update!(previous_aes_key_hex: "ee" * 32)

      envelope = poll

      expect { decrypt_inner(envelope, key: key_record.binary_previous_key) }.not_to raise_error
    end
  end

  describe "CMD (найпріоритетніший)" do
    let(:actuator) { create(:actuator, gateway: gateway) }
    let!(:command) { create(:actuator_command, actuator: actuator) }

    before { allow(ActuatorCommandWorker).to receive(:broadcast_command_state_static) }

    it "видає CMD-рядок у форматі воркера і проводить повний success-lifecycle" do
      inner = decrypt_inner(poll)

      expected = "CMD:#{command.command_payload}:#{command.duration_seconds}:" \
                 "#{command.actuator_id}:#{command.idempotency_token}"
      expect(inner.byteslice(0, expected.bytesize)).to eq(expected)

      command.reload
      expect(command.status).to eq("acknowledged")
      expect(actuator.reload.state).to eq("active")
      expect(ResetActuatorStateWorker.jobs.sole["args"]).to eq([ command.id ])
    end

    it "друга видача бере НАСТУПНУ команду (перша вже acknowledged)" do
      second = create(:actuator_command, actuator: actuator)

      first_inner = decrypt_inner(poll)
      second_inner = decrypt_inner(poll)

      expect(first_inner).to include(command.idempotency_token)
      expect(second_inner).to include(second.idempotency_token)
    end

    # 🔴 [ARCH.75] Єдина негативна гілка файла, що ВИКОНУВАЛАСЬ (branch-coverage чистий),
    # але не мала ІМЕНОВАНОГО піна — тобто трималась на сусідах. Гілка не косметична:
    # голий `mark_active!` на вже активному актуаторі кидає `AASM::InvalidTransition`,
    # а тут ми в синхронному reply-шляху coap-демона — виняток лишив би `reply`
    # непризначеним, тож poll помер би БЕЗ ВІДПОВІДІ разом із ratchet, OTA-hint і
    # time-sync. Подовження/override на активний пристрій — легальний потік, і саме
    # він найімовірніший під час пожежі.
    it "друга команда на ВЖЕ активний актуатор видається (подовження/override — легальний потік)" do
      actuator.update!(state: :active)

      expect(decrypt_inner(poll)).to include(command.idempotency_token)
      expect(command.reload.status).to eq("acknowledged")
      expect(actuator.reload.state).to eq("active")
    end

    it "протермінована команда фейлиться і пропускається (не блокує чергу)" do
      command.update_columns(expires_at: 1.minute.ago)

      inner = decrypt_inner(poll)

      expect(inner.bytes).to all(eq(0))
      expect(command.reload.status).to eq("failed")
    end

    it "CMD понад стелю конверта Queen фейлиться гучно, не тихо ріжеться" do
      # command_payload text — валідацію обходимо update_columns, як робив би
      # майбутній ширший формат; стеля = MAX_ENVELOPE_BYTES (560).
      command.update_columns(command_payload: "A" * 600)

      inner = decrypt_inner(poll)

      expect(inner.bytes).to all(eq(0))
      expect(command.reload.status).to eq("failed")
      expect(command.error_message).to include("стелю")
    end

    it "чужа команда (інший gateway) не видається" do
      command.update!(actuator: create(:actuator, gateway: create(:gateway, cluster: cluster)))

      expect(decrypt_inner(poll).bytes).to all(eq(0))
    end

    # 🔴 [ARCH.75] Найгостріший клас, знайдений виміром: `EmergencyResponseService`
    # пише `insert_all` (валідації обходить) і ріже тривалість за власною
    # константою 3600, не за `actuator.max_active_duration_s` — а сіди везуть
    # клапан зі стелею 300 і сирену зі 120. Тоді КОЖЕН AASM-перехід такого
    # наказу б'ється об валідацію, включно з TTL-прибиранням. Демон виняток
    # ЛОВИТЬ (`rescue StandardError`), але `reply` лишається непризначеним —
    # `socket.send` не відбувається: poll назавжди без відповіді, разом із ним
    # мертві ratchet, OTA-hint і time-sync шлюза.
    describe "наказ, який неможливо зберегти" do
      let(:capped) { create(:actuator, gateway: gateway, max_active_duration_s: 60) }

      before do
        ActuatorCommand.insert_all([ {
          actuator_id: capped.id, command_payload: "OPEN_VALVE", duration_seconds: 3600,
          status: ActuatorCommand.statuses[:issued], priority: ActuatorCommand.priorities[:high],
          idempotency_token: SecureRandom.uuid, expires_at: 15.minutes.from_now,
          created_at: Time.current, updated_at: Time.current
        } ])
      end

      it "не валить poll — конверт віддається" do
        expect { poll }.not_to raise_error
      end

      it "виносить невалідний наказ із черги як failed із причиною" do
        poll

        bad = capped.commands.sole
        expect(bad.reload.status).to eq("failed")
        expect(bad.error_message).to include("не проходить власну валідацію")
      end

      it "не блокує видачу ВАЛІДНОГО наказу того ж шлюза" do
        expect(decrypt_inner(poll)).to include("CMD:#{command.command_payload}")
      end

      # Невалідним у транзакції може виявитись АКТУАТОР (`mark_active!` — AASM
      # `whiny_persistence` → save! з валідаціями). Маркувати тоді команду
      # «невалідною» = брехати про винуватця й вигасити цілком доставну чергу
      # хворого актуатора по одній.
      it "не звинувачує наказ, коли невалідний сам актуатор" do
        sick = create(:actuator, gateway: gateway)
        good = create(:actuator_command, actuator: sick, duration_seconds: 30, priority: :high)
        sick.update_columns(name: nil)

        expect { poll }.not_to raise_error
        expect(good.reload.status).to eq("issued")
      end

      it "хворий актуатор не валить тракт — драбина віддає конверт нижчої сходинки" do
        sick = create(:actuator, gateway: gateway)
        create(:actuator_command, actuator: sick, duration_seconds: 30, priority: :high)
        sick.update_columns(name: nil)

        expect(decrypt_inner(poll).bytes).to all(eq(0))
      end

      it "протермінований невалідний наказ теж виноситься (fail! інакше б'ється об ту саму валідацію)" do
        capped.commands.sole.update_columns(expires_at: 1.minute.ago)

        expect { poll }.not_to raise_error
        expect(capped.commands.sole.reload.status).to eq("failed")
      end
    end
  end

  describe "0x9E ratchet (gated FW.17)" do
    let!(:tree) { create(:tree, cluster: cluster) }
    let!(:tree_key) do
      create(:hardware_key, :for_tree, tree: tree, key_version: 3,
             previous_aes_key_hex: "cd" * 16)
    end

    it "мовчить, поки FW17-гейт зачинений (той самий guard, що воркер)" do
      allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(false)

      expect(decrypt_inner(poll).bytes).to all(eq(0))
    end

    it "derivable з Dual-Key Grace: незавершена ротація → 0x9E(key_version)" do
      allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(true)

      inner = decrypt_inner(poll)

      expected = OtaPackagerService.build_rotate_key_block(3)
      expect(inner.byteslice(0, expected.bytesize)).to eq(expected)
    end
  end

  describe "OTA-hint + chunk-server" do
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

    before { gateway.update!(pending_firmware_id: firmware.id) }

    it "hint [0x9F][fw_id:4][total:2] + state=:updating з ota_started_at (ARCH.59-якір)" do
      inner = decrypt_inner(poll)

      expect(inner.getbyte(0)).to eq(0x9F)
      fw_id, total = inner.byteslice(1, 6).unpack("Nn")
      expect(fw_id).to eq(firmware.id)
      expect(total).to be > 0
      expect(gateway.reload.state).to eq("updating")
      expect(gateway.ota_started_at).to be_present
    end

    # [ARCH.59] Якір міряє вік КАМПАНІЇ, не вік передачі: його ставить диспетчер
    # при таргетингу, і перший hint НЕ сміє його обнулити. Інакше шлюз, що поллить
    # рідко, щоразу отримував би свіжий годинник — і кампанія, яка провисіла добу
    # без анонсу, діставала б повне вікно заново.
    it "зберігає якір диспетчера — перший hint його НЕ перезаписує" do
      dispatched_at = 3.hours.ago
      gateway.update!(ota_started_at: dispatched_at)

      poll

      expect(gateway.reload.ota_started_at).to be_within(1.second).of(dispatched_at)
    end

    it "CMD пріоритетніший за OTA-hint" do
      actuator = create(:actuator, gateway: gateway)
      create(:actuator_command, actuator: actuator)
      allow(ActuatorCommandWorker).to receive(:broadcast_command_state_static)

      expect(decrypt_inner(poll).byteslice(0, 4)).to eq("CMD:")
    end

    it "chunk-server віддає чанк за (v, ch) і nil поза межами/на чужу версію" do
      packages = OtaPackagerService.prepare(
        firmware, chunk_size: OtaTransmissionWorker::CHUNK_SIZE, cluster_id: cluster.id
      )[:packages].to_a

      fetched = described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" }
      )
      expect(decrypt_inner(fetched).byteslice(0, packages[0].bytesize)).to eq(packages[0])

      expect(described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => packages.size.to_s }
      )).to be_nil
      expect(described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => (firmware.id + 99).to_s, "ch" => "0" }
      )).to be_nil
    end

    # 🔴 [ARCH.75] Єдиний шлях цього файла, який не виконувався ЖОДНОГО разу —
    # виміряно coverage'ом, не оком (решта негативних гілок уже доведена сусідами
    # вище). Backstop стоїть на ВЖЕ ЗАШИФРОВАНОМУ конверті, і досяжний він лише
    # звідси: `oversized?(inner)` питається на CMD-сходинці, а чанк іде в `envelope`
    # без жодної перевірки розміру — тобто підняття `OtaTransmissionWorker::CHUNK_SIZE`
    # детонувало б саме тут. Вироджуємось у time-only (Королева лишається з живим
    # RTC-sync), а не шлемо конверт, який вона мовчки відкине ще до decrypt.
    it "чанк понад стелю конверта вироджується в time-only, а не їде на мовчазне відкидання" do
      stub_const("#{described_class}::MAX_ENVELOPE_BYTES", 40)

      fetched = described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" }
      )

      expect(fetched.bytesize).to eq(32)
      expect(decrypt_inner(fetched).bytes).to all(eq(0))
    end

    it "спостережене підтвердження: fw=<pending> глушить кампанію і ставить версію" do
      decrypt_inner(poll) # hint → updating

      poll({ "fw" => firmware.id.to_s })

      gateway.reload
      expect(gateway.pending_firmware_id).to be_nil
      expect(gateway.state).to eq("idle")
      expect(gateway.firmware_version).to eq(firmware.version)
    end

    it "fw=0 (ребут Королеви) НЕ глушить кампанію — hint повторюється (idempotent re-fetch)" do
      2.times { expect(decrypt_inner(poll({ "fw" => "0" })).getbyte(0)).to eq(0x9F) }

      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
    end
  end

  describe "[SEC.20] Turbo-прогрес кампанії (живий producer бара)" do
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

    before do
      gateway.update!(pending_firmware_id: firmware.id)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "hint мовить старт 0% TRANSMITTING у персональний канал шлюзу" do
      poll

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "ota_channel_#{gateway.uid}",
        hash_including(target: "ota_progress_#{gateway.uid}",
                       html: include(">TRANSMITTING<").and(include("width: 0%")))
      )
    end

    it "chunk-fetch мовить прогрес (ch+1 із total)" do
      total = OtaPackagerService.prepare(
        firmware, chunk_size: OtaTransmissionWorker::CHUNK_SIZE, cluster_id: cluster.id
      )[:packages].to_a.size

      described_class.ota_chunk_reply(gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" })

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "ota_channel_#{gateway.uid}",
        hash_including(html: include("CHUNK: 1 / #{total}"))
      )
    end

    it "fw=-підтвердження мовить COMPLETE 100% (total невідомий — без ділення на нуль)" do
      gateway.update!(state: :updating, ota_started_at: Time.current)

      poll({ "fw" => firmware.id.to_s })

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "ota_channel_#{gateway.uid}",
        hash_including(html: include(">COMPLETE<").and(include("width: 100%")))
      )
    end

    it "відхилений chunk-запит (чужа версія) НЕ мовить" do
      described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => (firmware.id + 99).to_s, "ch" => "0" }
      )

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it "0% мовиться лише на ПЕРШОМУ hint'і — re-hint не пиляє бар назад (Queen тримає курсор)" do
      2.times { poll }

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).once
    end

    it "збій Turbo-транспорту не вбиває конверт (rescue-ізоляція: UI-декорація ≠ доставка)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .and_raise(StandardError, "cable down")

      expect(decrypt_inner(poll).getbyte(0)).to eq(0x9F)

      fetched = described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" }
      )
      expect(fetched).not_to be_nil
    end
  end

  describe "[FW.60/SEC.11] OTA fail-closed без PROVISIONING_MASTER_KEY (SecurityError-ізоляція)" do
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

    before do
      gateway.update!(pending_firmware_id: firmware.id)
      # OtaHmacKeyService кидає SecurityError (< Exception, НЕ StandardError) без
      # PROVISIONING_MASTER_KEY — демон-rescue StandardError його НЕ ловить; без
      # guard'а це crash-loop усього CoAP-інтейку на першому hint/chunk кампанії.
      allow(OtaHmacKeyService).to receive(:fetch_binary_for)
        .and_raise(SecurityError, "PROVISIONING_MASTER_KEY ENV is required")
    end

    it "poll не падає: hint пропущено → time-only конверт (RTC-sync Королеви живий)" do
      expect { poll }.not_to raise_error
      expect(decrypt_inner(poll).bytes).to all(eq(0))
    end

    it "chunk-fetch fail-closed → nil (CoapGate відповість 4.04), демон не крашиться" do
      fetched = nil
      expect do
        fetched = described_class.ota_chunk_reply(
          gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" }
        )
      end.not_to raise_error
      expect(fetched).to be_nil
    end

    it "nil НЕ кешується — щойно ключ зʼявляється, hint оживає (без години зависання)" do
      poll # SecurityError → fail-closed nil; якби nil закешувався — hint застряг би

      allow(OtaHmacKeyService).to receive(:fetch_binary_for).and_call_original
      expect(decrypt_inner(poll).getbyte(0)).to eq(0x9F)
    end
  end
end
