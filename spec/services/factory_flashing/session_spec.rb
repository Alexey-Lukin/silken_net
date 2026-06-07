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
    let!(:session) { make_session(gilka: "B", atecc_serial_hex: "0123456789ABCDEF01") }

    it "also emits ATCA write-zone transcript" do
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(outcome.atecc_transcript).to be_a(FactoryFlashing::AteccProvisioner::Result)
      expect(outcome.atecc_transcript.statements).to include(a_string_matching(/Slot 0 AES-128 LoRa/))
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

  describe "Гілка B + Gateway device — ATCA provisioning skipped" do
    let(:gateway) { create(:gateway) }
    let!(:session) do
      make_session(gilka: "B", device_uid: gateway.uid, atecc_serial_hex: "0123456789ABCDEF01")
    end

    it "completes without running AteccProvisioner (gateway has no ATCA chip)" do
      expect(FactoryFlashing::AteccProvisioner).not_to receive(:new)
      outcome = described_class.run(
        session: session, executor: executor, master_key_source: master_key_source
      )
      expect(session.reload).to be_completed
      expect(outcome.atecc_transcript).to be_nil
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

      expect(Rails.logger).to receive(:error).with(a_string_matching(/Could not record session failure.*db down/))

      expect {
        service.send(:capture_failure, StandardError.new("boom"))
      }.not_to raise_error
    end
  end
end
