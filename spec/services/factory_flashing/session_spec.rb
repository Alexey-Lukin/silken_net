# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::Session do
  let(:operator)    { create(:user, :super_admin) }
  let(:supervisor)  { create(:user, :admin, organization: operator.organization) }
  let(:tree)        { create(:tree) }
  let(:executor)    { FactoryFlashing::Executor.new(io: StringIO.new) } # dry-run by default
  let(:master_key_source) do
    instance_double(FactoryFlashing::MasterKeySource::EnvAdapter).tap do |dbl|
      allow(dbl).to receive(:fetch_master_key).and_return("master")
    end
  end

  def make_session(state: "supervisor_approved", **overrides)
    create(:provisioning_session,
           operator: operator, supervisor: supervisor,
           device_uid: tree.did, state: state,
           supervisor_approved_at: Time.current,
           **overrides)
  end

  describe "happy path — Гілка A Tree (dry-run)" do
    let!(:session) { make_session(gilka: "A") }

    it "completes the session, persists HardwareKey, emits commands, writes AuditLog" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )

      session.reload
      expect(session).to be_completed
      expect(session.error_message).to be_nil
      expect(outcome.hardware_key).to be_persisted
      expect(outcome.transcript.size).to be > 1
      expect(outcome.transcript.first.command).to include("STM32_Programmer_CLI -c port=SWD")
      expect(outcome.audit_log).to be_persisted
      expect(outcome.audit_log.action).to eq("factory_flash")
    end
  end

  # [L1 QATT] Голос Королеви: Гілка-A Gateway отримує EDSK-сім'ю, у БД — лише pubkey
  describe "happy path — Гілка A Gateway (голос Королеви)" do
    let(:gateway)   { create(:gateway) }
    let!(:session)  { make_session(gilka: "A", device_uid: gateway.uid) }

    it "генерує сім'ю, шиє EDSK-блок і реєструє ЛИШЕ pubkey у HardwareKey" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )

      edsk_cmds = outcome.transcript.select { |r| r.command.include?("0x4544534B") }
      expect(edsk_cmds).not_to be_empty

      hw_key = outcome.hardware_key.reload
      expect(hw_key.ed25519_public_key_hex).to match(/\A[0-9a-f]{64}\z/)

      # Сім'я (32 байти, 8 слів) присутня у транскрипті процесу,
      # але деривований pubkey їй відповідає — звіримо незалежно:
      seed_words = outcome.transcript.map(&:command)
                          .select { |c| c.match?(/-w32 0x0803E0(6[8-9A-F]|7[0-9A-F]|8[0-4]) /) }
                          .map { |c| c.split.last.delete_prefix("0x") }
      seed_hex = seed_words.join
      expect(seed_hex.length).to eq(64)
      expect(Ed25519Crypto::SigningService.public_key_from_seed(seed_hex))
        .to eq(hw_key.ed25519_public_key_hex)
    end

    it "НЕ персистить сиру сім'ю в AuditLog (metadata без байтів ключів)" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(outcome.audit_log.metadata.to_json).not_to include("0x4544534B")
    end
  end

  describe "happy path — Гілка B Tree" do
    let!(:session) { make_session(gilka: "B", se_serial_hex: "0123456789ABCDEF01") }

    it "also emits ATCA write-zone transcript" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(outcome.se_transcript).to be_a(FactoryFlashing::SecureElementProvisioner::Result)
      expect(outcome.se_transcript.statements).to include(a_string_matching(/Slot 0 AES-128 LoRa/))
    end
  end

  describe "preflight" do
    it "refuses to run when session is :pending (no supervisor approval)" do
      session = make_session(state: "pending", supervisor_approved_at: nil)
      expect {
        described_class.run(session: session, executor: executor, master_key_source: master_key_source)
      }.to raise_error(described_class::PreflightError, /supervisor_approved/)
    end

    it "refuses to run when device cannot be located" do
      session = make_session(device_uid: "SNET-DEADBEEF") # tree not created
      expect {
        described_class.run(session: session, executor: executor, master_key_source: master_key_source)
      }.to raise_error(described_class::PreflightError, /not found/)
    end

    it "surfaces MasterKeySource::UnavailableError before opening the transaction" do
      bad_source = instance_double(FactoryFlashing::MasterKeySource::EnvAdapter)
      allow(bad_source).to receive(:fetch_master_key)
        .and_raise(FactoryFlashing::MasterKeySource::UnavailableError, "blank")
      session = make_session(gilka: "A")
      expect {
        described_class.run(session: session, executor: executor, master_key_source: bad_source)
      }.to raise_error(FactoryFlashing::MasterKeySource::UnavailableError)
      expect(HardwareKey.where(device_uid: session.device_uid)).to be_empty
    end
  end

  # [FW.54] verify_silicon_uid! parse-fail: маємо що звіряти (паспорт є,
  # live-режим), але read не розпарсився — відмова записом, не пишемо наосліп.
  describe "wrong-board guard: UID-read не розпарсився" do
    it "raises WrongBoardError (порожні results / stdout без адресного рядка)" do
      passport_tree = create(:tree, silicon_uid_hex: "0039002F3138511538323634")
      session = make_session(device_uid: passport_tree.did)
      live_executor = instance_double(FactoryFlashing::Executor, dry_run?: false, results: [])
      service = described_class.new(session: session, device: passport_tree,
                                    executor: live_executor, master_key_source: master_key_source)

      expect {
        service.send(:verify_silicon_uid!)
      }.to raise_error(described_class::WrongBoardError, /не розпарсився/)
    end
  end

  describe "failure recovery" do
    let!(:session) { make_session(gilka: "A") }

    it "rolls back HardwareKey/audit writes when executor fails" do
      bomb_executor = FactoryFlashing::Executor.new(io: StringIO.new, dry_run: false)
      allow(bomb_executor).to receive(:run).and_raise(FactoryFlashing::Executor::ProgrammerMissingError, "no SWD")

      expect {
        described_class.run(session: session, executor: bomb_executor, master_key_source: master_key_source)
      }.to raise_error(FactoryFlashing::Executor::ProgrammerMissingError)

      session.reload
      expect(session).to be_failed
      expect(session.error_message).to include("ProgrammerMissingError")
      expect(HardwareKey.where(device_uid: session.device_uid)).to be_empty
      expect(AuditLog.where(action: "factory_flash")).to be_empty
    end
  end

  describe "Zero-Trust" do
    let!(:session) { make_session(gilka: "A") }

    it "never returns the raw master key in Outcome" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(outcome.to_h.values.compact.to_s).not_to include("master")
    end
  end

  # [SEC.3 DI] Доказ, що адаптерний ключ реально живить деривацію: до
  # DI-рефакторингу деривація читала ENV-пін, ігноруючи MasterKeySource.
  describe "master-key DI — adapter key feeds derivation [SEC.3]" do
    let(:di_key) { "di-alive-proof-master-key-distinct" }
    let(:di_source) do
      instance_double(FactoryFlashing::MasterKeySource::EnvAdapter).tap do |dbl|
        allow(dbl).to receive(:fetch_master_key).and_return(di_key)
      end
    end

    it "Гілка A: HardwareKey ключі деривовані з адаптерного ключа, не з ENV" do
      session = make_session(gilka: "A")
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: di_source
      )

      hw = outcome.hardware_key
      expect(hw.aes_key_hex).not_to eq(HardwareKeyService.derive_lora_key(tree.did))
      oracle = OpenSSL::KDF.hkdf(
        di_key, salt: tree.did, info: HardwareKeyService::LORA_HKDF_INFO,
        length: HardwareKeyService::LORA_KEY_SIZE_BYTES, hash: "SHA256"
      ).unpack1("H*").upcase
      expect(hw.aes_key_hex).to eq(oracle)

      expect(hw.lorenz_seed_hex).not_to eq(SilkenNet::SeedDerivation.derive_seed(tree.did))
      expect(hw.lorenz_seed_hex).to eq(
        SilkenNet::SeedDerivation.derive_seed(tree.did, master_key: di_key)
      )
    end

    it "Гілка B: обидва OTA call-sites отримують адаптерний ключ" do
      session = make_session(gilka: "B", se_serial_hex: "0123456789ABCDEF01")
      allow(OtaHmacKeyService).to receive(:fetch_for)
        .with(tree.cluster_id, master_key: di_key).and_call_original

      described_class.run(session: session, executor: executor, master_key_source: di_source)

      expect(OtaHmacKeyService).to have_received(:fetch_for)
        .with(tree.cluster_id, master_key: di_key).at_least(:once)
    end
  end

  describe "Гілка B + Gateway device — ATCA provisioning skipped" do
    let(:gateway) { create(:gateway) }
    let!(:session) do
      make_session(gilka: "B", device_uid: gateway.uid, se_serial_hex: "0123456789ABCDEF01")
    end

    it "completes without running SecureElementProvisioner (gateway has no ATCA chip)" do
      allow(FactoryFlashing::SecureElementProvisioner).to receive(:new)
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(FactoryFlashing::SecureElementProvisioner).not_to have_received(:new)
      expect(session.reload).to be_completed
      expect(outcome.se_transcript).to be_nil
    end
  end

  describe "capture_failure edges" do
    let!(:session) { make_session(gilka: "A") }

    def build_service(src = master_key_source)
      described_class.new(session: session, device: nil, executor: executor, master_key_source: src)
    end

    it "does not re-fail an already-failed session (idempotent)" do
      session.update!(state: "supervisor_approved")
      session.fail_with!("prior reason")
      expect(session.reload).to be_failed

      service = build_service
      # Direct invocation — preflight would otherwise block a failed row.
      expect {
        service.send(:capture_failure, StandardError.new("late boom"))
      }.not_to(change { session.reload.error_message })
    end

    it "logs (does not re-raise) when persisting the failure itself raises" do
      service = build_service
      allow(session).to receive(:may_fail_with?).and_return(true)
      allow(session).to receive(:fail_with!).and_raise(ActiveRecord::StatementInvalid, "db down")
      service.instance_variable_set(:@session, session)

      allow(Rails.logger).to receive(:error).with(a_string_matching(/Could not record session failure.*db down/))

      expect {
        service.send(:capture_failure, StandardError.new("boom"))
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(a_string_matching(/Could not record session failure.*db down/))
    end
  end
end
