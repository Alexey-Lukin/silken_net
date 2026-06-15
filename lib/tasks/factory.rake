# frozen_string_literal: true

# [SEC.3] Factory Flashing Pipeline — operator CLI.
#
# Three-step workflow enforcing the 2-Person Rule documented in
# docs/03_06 §5 C:
#
#   rake factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]
#     → creates a ProvisioningSession in :pending and prints session id
#
#   rake factory:approve[session_id]
#     → supervisor moves :pending → :supervisor_approved
#
#   rake factory:execute[session_id]
#     → runs FactoryFlashing::Session.run (dry-run by default,
#       EXECUTE=1 spawns real subprocesses).
namespace :factory do
  desc "Create a Factory-Flashing session (status=pending). Args: device_uid, batch_id, gilka, operator_id, supervisor_id, firmware_version. Set ATECC_SERIAL=… for gilka=B."
  task :flash, %i[device_uid batch_id gilka operator_id supervisor_id firmware_version] => :environment do |_t, args|
    abort "Usage: rake factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]" if args.values_at(:device_uid, :batch_id, :gilka, :operator_id, :supervisor_id, :firmware_version).any?(&:blank?)

    session = ProvisioningSession.create!(
      device_uid:       args[:device_uid],
      batch_id:         args[:batch_id],
      gilka:            args[:gilka],
      operator_id:      Integer(args[:operator_id]),
      supervisor_id:    Integer(args[:supervisor_id]),
      firmware_version: args[:firmware_version],
      atecc_serial_hex: (args[:gilka] == "B" ? ENV["ATECC_SERIAL"] : nil),
      rdp_level:        Integer(ENV.fetch("RDP_LEVEL", 1))
    )
    puts "✅ Session ##{session.id} created (state=pending). Next: rake factory:approve[#{session.id}]"
  end

  desc "Supervisor authenticates + approves a pending session. Args: session_id. Requires SUPERVISOR_PASSWORD env (the supervisor's OWN password — 2-Person Rule, SEC.3)."
  task :approve, %i[session_id] => :environment do |_t, args|
    session = ProvisioningSession.find(Integer(args[:session_id]))
    password = ENV["SUPERVISOR_PASSWORD"]
    if password.blank?
      abort "SUPERVISOR_PASSWORD env required — supervisor ##{session.supervisor_id} must authenticate the approval (2-Person Rule, SEC.3)"
    end

    begin
      session.approve_with_credentials!(password)
    rescue ProvisioningSession::SupervisorAuthError => e
      abort "Approval rejected: #{e.message}"
    end

    puts "✅ Session ##{session.id} approved by supervisor ##{session.supervisor_id} (password-authenticated). Next: rake factory:execute[#{session.id}]"
  end

  desc "Execute a supervisor-approved session (dry-run unless EXECUTE=1). Args: session_id."
  task :execute, %i[session_id] => :environment do |_t, args|
    session = ProvisioningSession.find(Integer(args[:session_id]))
    dry_run = ENV["EXECUTE"] != "1"

    executor = FactoryFlashing::Executor.new(dry_run: dry_run)
    outcome  = FactoryFlashing::Session.run(session: session, executor: executor)

    puts "✅ Session ##{outcome.session.id} completed (gilka=#{outcome.session.gilka}, dry_run=#{dry_run})"
    puts "   HardwareKey:  ##{outcome.hardware_key.id}"
    puts "   AuditLog:     ##{outcome.audit_log.id}"
    puts "   Commands:     #{outcome.transcript.size}"
    if outcome.atecc_transcript
      puts "   ATCA stmts:   #{outcome.atecc_transcript.statements.size}"
    end
  end
end
