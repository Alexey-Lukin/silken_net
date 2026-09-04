# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.21 L1] Device-event 0x57: Королева форвардить cleartext-події під власним
# Ed25519-підписом (тег QEVT1); воркер верифікує gateway-origin проти Королевиного
# ed25519_public_key_hex — LoRa-ключа НЕ торкається. Spec підписує РЕАЛЬНИМ
# Gateway EDSK (не шифрує per-device — попередній spec тим маскував key-domain баг).
RSpec.describe DeviceEventWorker do
  let(:cluster)    { create(:cluster) }
  let(:gateway)    { create(:gateway, cluster: cluster) }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }
  let(:keypair)    { Ed25519Crypto::SigningService.generate_keypair }
  let(:tree)       { create(:tree, cluster: cluster) }

  before do
    key_record.update!(ed25519_public_key_hex: keypair[:public_key_hex])
    Rails.cache.clear
  end

  def did_int(t) = t.did.delete_prefix("SNET-").to_i(16)

  def record(t, code: 0x02, seq: 1)
    [ did_int(t) ].pack("N") + [ code ].pack("C") + [ seq ].pack("n")
  end

  # Дзеркало firmware/queen/main.c L1-sign: [ver][ts][count][records][sig],
  # msg = "SLKN-QEVT1"‖uid_len‖uid‖body.
  # `count:` окремо від `records.size` — щоб можна було підписати конверт, чий
  # header БРЕШЕ про кількість записів (межовий guard читає саме цей байт).
  def signed_envelope(seed_hex:, uid:, records:, ts: 1_750_000_000, ver: 0x01, count: records.size)
    header  = [ ver, ts, count ].pack("CNC")
    body    = header + records.join
    message = DeviceEventWorker::DEVENV_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body
    body + [ Ed25519Crypto::SigningService.sign(seed_hex, message) ].pack("H*")
  end

  def perform(payload, uid: gateway.uid)
    described_class.new.perform(Base64.strict_encode64(payload), uid)
  end

  def valid_payload(records: [ record(tree) ])
    signed_envelope(seed_hex: keypair[:seed_hex], uid: gateway.uid, records: records)
  end

  it "raises a critical firmware_canary_trip alert for a valid signed envelope" do
    expect { perform(valid_payload) }.to change(EwsAlert, :count).by(1)

    alert = EwsAlert.last
    expect(alert.alert_type).to eq("firmware_canary_trip")
    expect(alert.severity).to eq("critical")
    expect(alert.tree).to eq(tree)
    expect(alert.message_key).to eq("canary_trip")
      I18n.with_locale(:uk) { expect(alert.message).to include("КАНАРКА") }
  end

  it "drops an envelope signed by the WRONG key (gateway-origin fails)" do
    wrong = Ed25519Crypto::SigningService.generate_keypair
    payload = signed_envelope(seed_hex: wrong[:seed_hex], uid: gateway.uid, records: [ record(tree) ])
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "drops a tampered body (did flipped → signature no longer matches)" do
    payload = valid_payload.dup
    # Перший байт першого record'а (did MSB) — одразу за header'ом.
    payload.setbyte(DeviceEventWorker::DEVENV_HEADER_LEN,
                    payload.getbyte(DeviceEventWorker::DEVENV_HEADER_LEN) ^ 0xFF)
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "dedups a replayed envelope via the signature nonce" do
    payload = valid_payload
    expect { perform(payload) }.to change(EwsAlert, :count).by(1)
    EwsAlert.last.update!(status: :resolved) # звільнити uniqueness [tree,type,status]
    expect { perform(payload) }.not_to change(EwsAlert, :count) # той самий sig → nonce skip
  end

  # =========================================================================
  # [ARCH.105] Двофазний nonce. Однофазний спалював би токен ДО диспетчу, тож
  # будь-який raise усередині нього віддавав би батч у Sidekiq-retry, де claim
  # уже сказав би «бачив» — підписаний батч із tamper-кодом зникав би мовчки.
  # `jid` тут не декорація: Sidekiq зберігає його на ретраях, і саме він
  # відрізняє власний краш від чужого реплею.
  # =========================================================================
  def perform_as(jid, payload)
    worker = described_class.new
    worker.jid = jid
    worker.perform(Base64.strict_encode64(payload), gateway.uid)
  end

  it "re-processes its OWN batch after a crash mid-dispatch (nonce not burned)" do
    payload = valid_payload
    jid     = SecureRandom.hex(12)

    allow(EwsAlert).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "deadlock detected")
    expect { perform_as(jid, payload) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(EwsAlert.count).to eq(0)

    # Sidekiq ретраїть ТОЙ САМИЙ джоб — той самий `jid`.
    allow(EwsAlert).to receive(:create!).and_call_original
    expect { perform_as(jid, payload) }.to change(EwsAlert, :count).by(1)
  end

  it "denies a DIFFERENT job the resume, even mid-flight (only the owner resumes)" do
    payload = valid_payload

    allow(EwsAlert).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "deadlock detected")
    expect { perform_as("owner-jid", payload) }.to raise_error(ActiveRecord::StatementInvalid)

    # Чужий джоб на той самий підпис — це реплей, а не резюме.
    allow(EwsAlert).to receive(:create!).and_call_original
    expect { perform_as("someone-else-jid", payload) }.not_to change(EwsAlert, :count)
  end

  it "closes the batch on success — even its own jid cannot resume afterwards" do
    payload = valid_payload
    jid     = SecureRandom.hex(12)

    expect { perform_as(jid, payload) }.to change(EwsAlert, :count).by(1)
    EwsAlert.last.update!(status: :resolved) # звільнити uniqueness [tree,type,status]

    expect { perform_as(jid, payload) }.not_to change(EwsAlert, :count)
  end

  it "processes multiple records — one alert per distinct tree" do
    tree2 = create(:tree, cluster: cluster)
    payload = valid_payload(records: [ record(tree), record(tree2) ])
    expect { perform(payload) }.to change(EwsAlert, :count).by(2)
  end

  it "treats an unregistered gateway pubkey as non-verifiable (skip, no crash)" do
    key_record.update_columns(ed25519_public_key_hex: nil)
    expect { perform(valid_payload) }.not_to change(EwsAlert, :count)
  end

  # Сусід попереднього, але ІНШИЙ стан registry: там рядок ключа є з порожнім
  # pubkey, тут його немає ЗОВСІМ (шлюз заведено, але жодного разу не провіжено).
  it "drops an envelope from a gateway with NO hardware-key row at all" do
    payload = valid_payload # будує підпис ДОКИ ключ ще існує
    key_record.destroy!
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  # count у ПІДПИСАНОМУ header'і довірений за походженням, але не за величиною:
  # бита Королева з валідним підписом не сміє вивести читання за буфер.
  it "drops an envelope whose count byte over-claims the record block" do
    payload = signed_envelope(seed_hex: keypair[:seed_hex], uid: gateway.uid,
                              records: [ record(tree) ], count: 3)
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "skips an unknown gateway" do
    payload = valid_payload
    expect { perform(payload, uid: "SNET-Q-DEADBEEF") }.not_to change(EwsAlert, :count)
  end

  it "drops a record whose tree is in ANOTHER cluster (ops-spoof guard)" do
    foreign = create(:tree, cluster: create(:cluster)) # чужий кластер
    payload = valid_payload(records: [ record(foreign) ])
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "drops a record whose tree has no cluster (would crash notification worker)" do
    lone = create(:tree, cluster: nil)
    payload = valid_payload(records: [ record(lone) ])
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "warns (no alert) when a record's DID is unknown to the registry" do
    ghost = create(:tree, cluster: cluster)
    did   = did_int(ghost)
    ghost.destroy
    payload = signed_envelope(seed_hex: keypair[:seed_hex], uid: gateway.uid,
                              records: [ [ did ].pack("N") + [ 0x02 ].pack("C") + [ 1 ].pack("n") ])
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "warns (no alert) on an unknown event code" do
    payload = valid_payload(records: [ record(tree, code: 0x7F) ])
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  it "ignores malformed Base64 without raising" do
    expect { described_class.new.perform("!!!not base64!!!", gateway.uid) }
      .not_to change(EwsAlert, :count)
  end

  it "ignores a too-short payload (below header+sig floor)" do
    expect { perform("\x01".b * 10) }.not_to change(EwsAlert, :count)
  end

  it "ignores a wrong version byte" do
    payload = valid_payload.dup
    payload.setbyte(0, 0x99)
    expect { perform(payload) }.not_to change(EwsAlert, :count)
  end

  # ⛔ [SILENCE-1 / ARCH.109] НОСІЙ присуду «канал живості пише лише той, хто почув
  # САМЕ ЦЕЙ вузол». Доти заборона жила ЛИШЕ коментарем над `dispatch_one`, тобто
  # дописаний `tree.mark_seen!` проходив би зеленим — а він ховає дерево від
  # `Tree.silent`, робить `fresh_signal?` істинним і гасить dead-man switch, тобто
  # відтворює ARCH.109 машинною рукою замість людської (`06_08 §1.3`).
  # 🔴 Пін навмисно доводить ОБИДВІ половини одним прикладом: що тракт ДІЙШОВ до
  # дерева (алерт створено) і що канал живості при цьому не торкнутий. Без першої
  # половини він був би зелений на порожній множині — на будь-якому дропі теж.
  describe "канал живості дерева [ARCH.109]" do
    it "обробляє подію ДО кінця, але last_seen_at не штампує" do
      tree.update_columns(last_seen_at: nil)

      expect { perform(valid_payload) }.to change(EwsAlert, :count).by(1)

      expect(tree.reload.last_seen_at).to be_nil
    end

    it "не оживляє мовчазне дерево — воно лишається в Tree.silent" do
      tree.update_columns(last_seen_at: 30.hours.ago)

      perform(valid_payload)

      expect(Tree.silent(24.hours)).to include(tree.reload)
    end
  end
end
