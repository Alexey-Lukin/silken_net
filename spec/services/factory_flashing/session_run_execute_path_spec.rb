# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.3] EXECUTE-шлях із fake STM32_Programmer_CLI — інтеграція без заліза.
#
# Unit-спеки Executor мокають Open3; тут навпаки — РЕАЛЬНИЙ fork/exec у
# шим-бінарник на PATH. Доводимо software-половину "real CLI execution":
# повну Session-оркестрацію (HKDF row → CommandBuilder → subprocess →
# AuditTrail transcript → AASM), capture stdout/stderr/exit, stop-on-fail
# порядок. Bench-residual SEC.3 звужується до фізичного SWD-флешу.
#
# Сценарії шима керуються ENV: FAKE_STM32_MODE = ok | verify_fail | rdp_fail.
RSpec.describe FactoryFlashing::Session, ".run", type: :service do
  let(:operator)   { create(:user, :super_admin) }
  let(:supervisor) { create(:user, :admin, organization: operator.organization) }
  let(:tree)       { create(:tree) }
  let(:master_key_source) do
    instance_double(FactoryFlashing::MasterKeySource::EnvAdapter).tap do |dbl|
      allow(dbl).to receive(:fetch_master_key).and_return("master")
    end
  end

  def make_session(**overrides)
    create(:provisioning_session,
           operator: operator, supervisor: supervisor,
           device_uid: tree.did, state: "supervisor_approved",
           supervisor_approved_at: Time.current,
           gilka: "A",
           **overrides)
  end

  # Шим пише кожен arg-vector у лог-файл — тести звіряють порядок і обрив.
  def shim_script
    <<~SH
      #!/bin/sh
      echo "$@" >> "$FAKE_STM32_LOG"
      case "$@" in
        *"-r32 0x1FFF7590"*) echo "0x1FFF7590 : 0039002F 31385115 38323634";;
      esac
      case "$FAKE_STM32_MODE" in
        verify_fail)
          case "$@" in
            *"-w32 0x0803E000"*) echo "Error: Data mismatch found at 0x0803E014" >&2; exit 7;;
          esac;;
        rdp_fail)
          case "$@" in
            *"-ob RDP="*) echo "Error: Target lost connection during option-bytes" >&2; exit 21;;
          esac;;
      esac
      echo "FAKE-CLI OK: $1 $2"
      exit 0
    SH
  end

  around do |example|
    Dir.mktmpdir("fake-stm32-") do |dir|
      exe = File.join(dir, "STM32_Programmer_CLI")
      File.write(exe, shim_script)
      File.chmod(0o755, exe)

      orig_path = ENV["PATH"]
      orig_mode = ENV["FAKE_STM32_MODE"]
      orig_log  = ENV["FAKE_STM32_LOG"]
      begin
        ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{orig_path}"
        ENV["FAKE_STM32_LOG"] = File.join(dir, "invocations.log")
        ENV["FAKE_STM32_MODE"] = "ok"
        example.run
      ensure
        ENV["PATH"] = orig_path
        ENV["FAKE_STM32_MODE"] = orig_mode
        ENV["FAKE_STM32_LOG"] = orig_log
      end
    end
  end

  def shim_invocations
    path = ENV.fetch("FAKE_STM32_LOG")
    File.exist?(path) ? File.readlines(path, chomp: true) : []
  end

  describe "happy path (FAKE_STM32_MODE=ok)" do
    it "runs the full Session through real subprocesses and lands :completed" do
      session = make_session
      outcome = described_class.run(
        session: session,
        executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
        master_key_source: master_key_source
      )

      expect(session.reload).to be_completed

      # Кожна команда реально виконалась і захоплена з живим stdout/exit 0
      expect(outcome.transcript).to all(have_attributes(status: 0))
      expect(outcome.transcript.map(&:stdout)).to all(include("FAKE-CLI OK"))

      # Кожен виклик під'єднується сам: UID-read → стирання → запис → IWDG-заморозка → RDP
      log = shim_invocations
      expect(log.size).to eq(outcome.transcript.size)
      expect(log).to all(start_with("-c port=SWD reset=HWrst "))
      expect(log.first).to include("-r32 0x1FFF7590")
      expect(log).to include(a_string_matching(/-w32 0x0803E000 0x4B45594C /)) # KEYL magic
      expect(log.last).to include("-ob RDP=")

      expect(outcome.audit_log).to be_persisted
    end
  end

  # [SEC.3] Залитий поточний KEYC — єдина доставка ротованого ключа Королеві,
  # тож Dual-Key Grace шлюзу закриває сесія, а не uplink (CBC без MAC ключа не
  # підтверджує — HardwareKey#coap_binary_key).
  describe "re-provision after a key rotation (Dual-Key Grace)" do
    def rotated_key_for(device)
      HardwareKeyService.provision(device, master_key: "master")
      HardwareKey.find_by!(device_uid: device.respond_to?(:did) ? device.did : device.uid).tap do |k|
        k.update!(previous_aes_key_hex: k.aes_key_hex,
                  aes_key_hex: SecureRandom.hex(k.aes_key_hex.length / 2).upcase)
      end
    end

    let(:gateway) { create(:gateway) }

    it "flashes the CURRENT KEYC into a Queen and closes her grace" do
      hw_key  = rotated_key_for(gateway)
      session = make_session(device_uid: gateway.uid)

      described_class.run(session: session,
                          executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
                          master_key_source: master_key_source)

      expect(flash_image(shim_invocations)[0x0803E044]).to eq("0x#{hw_key.aes_key_hex[0, 8]}")
      expect(hw_key.reload.previous_aes_key_hex).to be_nil
    end

    it "keeps the Queen's grace open on a dry run — nothing was flashed" do
      hw_key = rotated_key_for(gateway)

      described_class.run(session: make_session(device_uid: gateway.uid),
                          executor: FactoryFlashing::Executor.new(io: StringIO.new),
                          master_key_source: master_key_source)

      expect(hw_key.reload.previous_aes_key_hex).to be_present
    end

    it "leaves a tree's grace to the MIC" do
      hw_key = rotated_key_for(tree)

      described_class.run(session: make_session,
                          executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
                          master_key_source: master_key_source)

      expect(hw_key.reload.previous_aes_key_hex).to be_present
    end
  end

  # [FW.54] Wrong-board guard: шим завжди віддає g1-UID (0039002F…3634) на
  # -r32 — долю сесії вирішує кремнієвий паспорт дерева.
  describe "UID-verify (live wrong-board guard, FW.54)" do
    let(:g1_uid) { "0039002F3138511538323634" }

    it "паспорт збігається → completed, транскрипт містить -r32" do
      passport_tree = create(:tree, did: "SNET-80B12004", silicon_uid_hex: g1_uid)
      session = make_session(device_uid: passport_tree.did)

      described_class.run(
        session: session,
        executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
        master_key_source: master_key_source
      )

      expect(session.reload).to be_completed
      expect(shim_invocations).to include(a_string_matching(/-r32 0x1FFF7590/))
    end

    it "чужа плата → WrongBoardError ДО першого -w32, сесія failed, ключі не матеріалізовані" do
      passport_tree = create(:tree, did: "SNET-0BADF00D", silicon_uid_hex: "AAAAAAAABBBBBBBBCCCCCCCC")
      session = make_session(device_uid: passport_tree.did)

      expect {
        described_class.run(
          session: session,
          executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
          master_key_source: master_key_source
        )
      }.to raise_error(FactoryFlashing::Session::WrongBoardError, /чужа плата/)

      expect(session.reload).to be_failed
      expect(shim_invocations.grep(/-w32/)).to be_empty
      expect(HardwareKey.where(device_uid: passport_tree.did)).to be_empty
    end
  end

  describe "verify-fail посеред послідовності (FAKE_STM32_MODE=verify_fail)" do
    it "stops at the failed write, fails the session, leaves no further invocations" do
      ENV["FAKE_STM32_MODE"] = "verify_fail"
      session = make_session

      expect {
        described_class.run(
          session: session,
          executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
          master_key_source: master_key_source
        )
      }.to raise_error(FactoryFlashing::Executor::CommandFailedError, /exit=7.*mismatch/i)

      expect(session.reload).to be_failed
      expect(session.error_message).to include("CommandFailedError")
      # error_message персиститься — даних `-w32` (ключів) у ньому немає
      expect(session.error_message).not_to match(/-w32 0x\h+ 0x\h+/)

      # Stop-on-fail: після впалого запису стор. 124 ні IWDG, ні RDP не виконувались
      log = shim_invocations
      expect(log.last).to include("-w32 0x0803E000")
      expect(log.grep(/-ob /)).to be_empty
    end
  end

  describe "RDP-крок падає (FAKE_STM32_MODE=rdp_fail)" do
    it "captures stderr from the real process in the raised error" do
      ENV["FAKE_STM32_MODE"] = "rdp_fail"
      session = make_session

      expect {
        described_class.run(
          session: session,
          executor: FactoryFlashing::Executor.new(dry_run: false, io: StringIO.new),
          master_key_source: master_key_source
        )
      }.to raise_error(FactoryFlashing::Executor::CommandFailedError, /exit=21.*Target lost/i)

      expect(session.reload).to be_failed
    end
  end
end
