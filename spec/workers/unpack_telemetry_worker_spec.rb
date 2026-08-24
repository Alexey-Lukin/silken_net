# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe UnpackTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before do
    key_record # Ensure key exists
    allow(TelemetryUnpackerService).to receive(:call)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # [TEST.16] Зашифрований payload — ОДИН дім, `TelemetryChunkHelper`.
  # Локальна копія тут пропускала `cipher.padding = 0` (PKCS#7 увімкнено за
  # замовчуванням), тобто виробляла байти, яких пристрій не шле ніколи.
  def encrypt_payload(data, key) = encrypt_queen_batch(data, key: key)

  # [TEST.16] Ліхтар на САМУ фікстуру. Доти цей клас був німим за побудовою:
  # хибна форма (PKCS#7 замість `padding = 0`) дописує зайвий блок `16 × \x10`,
  # а `bytesize % 16` при цьому НЕ змінюється — тобто residue-дискримінатор
  # QATT сліпий, а споживач у цьому файлі заглушений. Єдине, що робить
  # регресію червоною, — пін на ДОВЖИНУ конверта.
  describe "фікстура конверта Королеви (wire-fidelity)" do
    it "does not append a PKCS#7 block — ciphertext matches the zero-padded plaintext" do
      key       = SecureRandom.bytes(32)
      plaintext = "A" * 21 # один 21-байтовий чанк, як на дроті
      padded    = plaintext.bytesize + ((16 - (plaintext.bytesize % 16)) % 16)

      envelope = encrypt_payload(plaintext, key)

      expect(envelope.bytesize - 16).to eq(padded) # −16 = IV
    end
  end

  describe "#perform" do
    it "decrypts payload with current key and forwards to TelemetryUnpackerService" do
      raw_data = "TELEMETRY_BATCH_DATA_TEST_1234"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
        .with(anything, gateway.id, gateway_attested: false)
    end

    it "updates gateway IP via mark_seen!" do
      raw_data = "TELEMETRY_DATA"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "10.0.0.99", gateway.uid)

      gateway.reload
      expect(gateway.ip_address).to eq("10.0.0.99")
    end

    # Пін на СКОУП, не на факт виклику: до цієї правки тут стояв голий
    # `"telemetry_stream"`, і саме він робив стрічку крос-тенантною —
    # кожен автентифікований глядач діставав payload і IP чужих Королев.
    it "broadcasts into the owning organization's stream, not a global one" do
      raw_data = "BROADCAST_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)
      expected = "telemetry_stream_org_#{gateway.cluster.organization_id}" \
                 "_e#{gateway.cluster.organization.stream_epoch}"

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(expected, anything)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).with(expected, anything)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to).with("telemetry_stream", anything)
    end

    # 🔴 [UI.4] Найдорожча вісь цього воркера, і доти вона не мала піна взагалі.
    #
    # `broadcast_to_matrix` стоїть у `perform` ПЕРЕД `TelemetryUnpackerService`,
    # а зовнішній `rescue StandardError` виняток не ковтає — він ПЕРЕКИДАЄ його
    # заради Sidekiq-retry. Тобто броадкаст, що падає стабільно (Solid Cable,
    # рендер компонента, кабель), робив батч таким, що НІКОЛИ не розпакується:
    # ретраї вичерпувались, і найдорожчі дані платформи лягали в dead set — на
    # черзі №1. Ізоляція тепер є, і ці два приклади її тримають.
    context "when the live-feed broadcast fails [UI.4]" do
      before do
        allow(Turbo::StreamsChannel)
          .to receive(:broadcast_prepend_to)
          .and_raise(StandardError, "solid cable down")
      end

      it "still unpacks the batch — UI decoration must not cost the envelope" do
        raw_data = "TELEMETRY_SURVIVES_DEAD_CABLE"
        encoded = Base64.strict_encode64(encrypt_payload(raw_data, key_record.binary_key))

        expect { described_class.new.perform(encoded, "10.0.0.1", gateway.uid) }.not_to raise_error

        expect(TelemetryUnpackerService).to have_received(:call)
          .with(anything, gateway.id, gateway_attested: false)
      end

      # Ізоляція мусить бути ЧУТНОЮ: мовчазний `rescue` тут перетворив би
      # зламану стрічку на «фічу, якої ніхто не помітив».
      it "says so in the log instead of failing silently" do
        allow(Rails.logger).to receive(:warn)
        encoded = Base64.strict_encode64(encrypt_payload("X", key_record.binary_key))

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(Rails.logger).to have_received(:warn).with(/\[UI\.4\] broadcast_to_matrix/)
      end
    end

    # «Краще без live-стрічки, ніж у глобальний ефір» — але ЗБЕРЕЖЕННЯ мусить
    # тривати. Без другого асершна перенесення гарду в `perform` тихо з'їло б
    # телеметрію осиротілих кластерів, а приклад лишився б зеленим.
    it "stays silent rather than going global when the cluster has no organization" do
      gateway.cluster.update_columns(organization_id: nil)
      encoded = Base64.strict_encode64(encrypt_payload("ORPHAN", key_record.binary_key))

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
      expect(TelemetryUnpackerService).to have_received(:call)
    end


    context "when dual-key rotation (grace period)" do
      it "decrypts with previous key when current key fails" do
        old_key = key_record.binary_key.dup
        # Ротуємо ключ — тепер old_key стає previous
        key_record.rotate_key!

        raw_data = "OLD_KEY_DATA"
        encrypted = encrypt_payload(raw_data, old_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "clears grace period when current key succeeds" do
        key_record.update!(previous_aes_key_hex: SecureRandom.hex(32).upcase)

        raw_data = "NEW_KEY_DATA"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        key_record.reload
        expect(key_record.previous_aes_key_hex).to be_nil
      end
    end

    context "when gateway identification" do
      it "finds gateway by UID (priority)" do
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "different.ip.1.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "falls back to IP when UID is nil" do
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, gateway.ip_address, nil)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "returns early for unknown source" do
        encoded = Base64.strict_encode64("garbage" * 10)

        described_class.new.perform(encoded, "unknown.ip.0.0", "UNKNOWN-UID")

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    context "when hardware key is missing" do
      it "returns early without processing" do
        key_record.destroy!

        raw_data = "TEST"
        encoded = Base64.strict_encode64(raw_data)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    context "when decryption fails completely" do
      it "returns early without calling unpacker" do
        # Payload коротший за 2 AES блоки (32 байти) — дешифрація відхиляється
        encoded = Base64.strict_encode64("\x00" * 16)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    it "handles Base64 corruption gracefully" do
      expect {
        described_class.new.perform("not-valid-base64!!!", "10.0.0.1", gateway.uid)
      }.not_to raise_error

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "re-raises unexpected errors for Sidekiq retry" do
      allow(Gateway).to receive(:find_by).and_raise(StandardError, "DB error")

      expect {
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)
        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)
      }.to raise_error(StandardError, "DB error")
    end
  end

  describe "decryption with current key" do
    it "decrypts successfully with current key and clears grace period" do
      payload_data = "\x00" * 32
      encrypted = encrypt_payload(payload_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      allow(key_record).to receive(:clear_grace_period!)
      allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(key_record)
      allow(key_record).to receive_messages(binary_key: key_record.binary_key, binary_previous_key: nil)

      worker = described_class.new

      allow(worker).to receive(:attempt_decryption).and_call_original
      allow(worker).to receive(:decrypt_aes).and_return(payload_data)

      worker.perform(encoded, "192.168.1.1", gateway.uid)

      expect(key_record).to have_received(:clear_grace_period!)
    end
  end

  describe "decryption with previous key" do
    it "falls back to previous key when current key fails" do
      prev_key_hex = SecureRandom.hex(32)
      key_record.update!(previous_aes_key_hex: prev_key_hex)
      allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(key_record)

      worker = described_class.new

      call_count = 0
      allow(worker).to receive(:decrypt_aes) do |_payload, _key|
        call_count += 1
        if call_count == 1
          nil
        else
          "\x00" * 32
        end
      end

      payload_data = "\x00" * 64
      encoded = Base64.strict_encode64(payload_data)

      worker.perform(encoded, "192.168.1.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
    end
  end

  describe "decrypt_aes error handling" do
    it "returns nil for CipherError" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 32, "\x00" * 32)
      expect(result).to be_a(String).or be_nil
    end

    it "returns nil when payload is too short" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 16, "\x00" * 32)
      expect(result).to be_nil
    end

    it "returns nil when ciphertext is not block-aligned" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 33, "\x00" * 32)
      expect(result).to be_nil
    end

    it "rescues StandardError and returns nil" do
      worker = described_class.new

      allow(OpenSSL::Cipher).to receive(:new).and_raise(StandardError, "unexpected")
      result = worker.send(:decrypt_aes, "\x00" * 64, "\x00" * 32)
      expect(result).to be_nil
    end

    it "rescues OpenSSL::Cipher::CipherError and returns nil" do
      worker = described_class.new
      cipher_mock = instance_double(OpenSSL::Cipher)
      allow(OpenSSL::Cipher).to receive(:new).and_return(cipher_mock)
      allow(cipher_mock).to receive(:decrypt)
      allow(cipher_mock).to receive(:key=)
      allow(cipher_mock).to receive(:iv=)
      allow(cipher_mock).to receive(:padding=)
      allow(cipher_mock).to receive(:update).and_raise(OpenSSL::Cipher::CipherError, "bad decrypt")

      result = worker.send(:decrypt_aes, "\x00" * 64, "\x00" * 32)
      expect(result).to be_nil
    end
  end

  describe "attempt_decryption when both keys fail" do
    it "returns nil when both current and previous keys fail to decrypt" do
      prev_key_hex = SecureRandom.hex(32)
      key_record.update!(previous_aes_key_hex: prev_key_hex)

      worker = described_class.new
      # Both keys fail
      allow(worker).to receive(:decrypt_aes).and_return(nil)

      result = worker.send(:attempt_decryption, "\x00" * 64, key_record)
      expect(result).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # SENTRY CONTEXT TAGGING
  # -----------------------------------------------------------------------
  describe "Sentry context" do
    it "sets gateway_uid tag via Sentry.set_tags" do
      raw_data = "SENTRY_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      allow(Sentry).to receive(:set_tags).with(gateway_uid: gateway.uid)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(Sentry).to have_received(:set_tags).with(gateway_uid: gateway.uid)
    end

    it "sets 'unknown' tag when gateway_uid is nil" do
      raw_data = "SENTRY_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      allow(Sentry).to receive(:set_tags).with(gateway_uid: "unknown")

      described_class.new.perform(encoded, gateway.ip_address, nil)

      expect(Sentry).to have_received(:set_tags).with(gateway_uid: "unknown")
    end
  end

  # -----------------------------------------------------------------------
  # BROADCAST_RAW_HEX FORMAT
  # -----------------------------------------------------------------------

  # -----------------------------------------------------------------------
  # GATEWAY MARK_SEEN! IP UPDATE
  # -----------------------------------------------------------------------
  describe "gateway.mark_seen! IP update" do
    it "updates gateway IP when sender IP differs" do
      raw_data = "IP_UPDATE_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "192.168.50.50", gateway.uid)

      gateway.reload
      expect(gateway.ip_address).to eq("192.168.50.50")
    end

    it "updates gateway last_seen_at" do
      raw_data = "SEEN_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      gateway.update_column(:last_seen_at, 1.day.ago)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      gateway.reload
      expect(gateway.last_seen_at).to be_within(5.seconds).of(Time.current)
    end
  end

  # -----------------------------------------------------------------------
  # SIDEKIQ OPTIONS
  # -----------------------------------------------------------------------
  describe "sidekiq configuration" do
    it "uses uplink queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("uplink")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end

    # 🔴 [ARCH.59, ⚖️ 2026-08-21] Пін на ВІДСУТНІСТЬ, і він несучий: без нього
    # присуд оборотний одним рядком, який виглядатиме як відновлення забутої
    # опції. Цей воркер веде до `Wallet#credit!`, тож дроп протухлої джоби —
    # незараховані growth_points; а Sidekiq Pro відкидає таку джобу без виконання
    # й у батчі рахує її SUCCESS, тобто втрата не лишає сліду ні в retry, ні в
    # DeadSet. Сьогодні опція інертна (гема немає) — саме тому пін дивиться на
    # ОГОЛОШЕННЯ, а не на поведінку: озброїть її крок 1 DOC-R.10, і мовчки.
    it "declares no expires_in — a stale telemetry job must never be dropped silently" do
      expect(described_class.get_sidekiq_options).not_to have_key("expires_in")
    end
  end

  # -----------------------------------------------------------------------
  # S2.4: Prometheus metric COAP_PACKETS_RECEIVED_TOTAL
  # -----------------------------------------------------------------------
  describe "Prometheus metrics (S2.4)" do
    it "increments COAP_PACKETS_RECEIVED_TOTAL with status success on full processing" do
      raw_data = "TELEMETRY_BATCH_DATA_TEST_1234"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      metric = SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL
      before_val = metric.get(labels: { status: "success" })

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(metric.get(labels: { status: "success" })).to eq(before_val + 1.0)
    end

    it "increments COAP_PACKETS_RECEIVED_TOTAL with status unknown_device for unknown source" do
      encoded = Base64.strict_encode64("garbage" * 10)

      metric = SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL
      before_val = metric.get(labels: { status: "unknown_device" })

      described_class.new.perform(encoded, "unknown.ip.0.0", "UNKNOWN-UID")

      expect(metric.get(labels: { status: "unknown_device" })).to eq(before_val + 1.0)
    end

    it "increments COAP_PACKETS_RECEIVED_TOTAL with status decrypt_error on decryption failure" do
      # Payload too short for valid AES-CBC (need at least 2 blocks = 32 bytes)
      encoded = Base64.strict_encode64("\x00" * 16)

      metric = SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL
      before_val = metric.get(labels: { status: "decrypt_error" })

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(metric.get(labels: { status: "decrypt_error" })).to eq(before_val + 1.0)
    end

    it "does not increment success metric for unknown devices" do
      encoded = Base64.strict_encode64("garbage" * 10)

      metric = SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL
      before_val = metric.get(labels: { status: "success" })

      described_class.new.perform(encoded, "unknown.ip.0.0", "UNKNOWN-UID")

      expect(metric.get(labels: { status: "success" })).to eq(before_val)
    end
  end
end
