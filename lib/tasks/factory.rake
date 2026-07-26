# SPDX-License-Identifier: AGPL-3.0-or-later
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
  desc "Create a Factory-Flashing session (status=pending). Args: device_uid (Tree = 24-hex silicon UID; Gateway = uid), batch_id, gilka, operator_id, supervisor_id, firmware_version. Tree-create: CLUSTER_ID + TREE_FAMILY_ID env. Set ATECC_SERIAL=… for gilka=B."
  task :flash, %i[device_uid batch_id gilka operator_id supervisor_id firmware_version] => :environment do |_t, args|
    abort "Usage: rake factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]" if args.values_at(:device_uid, :batch_id, :gilka, :operator_id, :supervisor_id, :firmware_version).any?(&:blank?)

    # [FW.54] Tree-провіженінг однопрохідний: у позиції device_uid — 24-hex
    # кремнієвий UID (SWD-read: `STM32_Programmer_CLI -r32 0x1FFF7590 12`);
    # DID деривується тут (murmur3-fmix32, 03_01 §7), Tree resolve'иться
    # (create → CLUSTER_ID + TREE_FAMILY_ID env). Голий "SNET-" DID
    # приймається лише для дерева, що ВЖЕ має кремнієвий паспорт (re-flash),
    # та для Gateway (як досі).
    identifier = args[:device_uid].to_s.strip.upcase
    device_uid =
      if SilkenNet::DidDerivation::UID_HEX_FORMAT.match?(identifier)
        begin
          tree = FactoryFlashing::TreeResolver.resolve!(
            uid_hex:        identifier,
            cluster_id:     ENV["CLUSTER_ID"],
            tree_family_id: ENV["TREE_FAMILY_ID"]
          )
        rescue FactoryFlashing::TreeResolver::CollisionError,
               FactoryFlashing::TreeResolver::MissingAttributesError,
               ArgumentError => e
          abort "⛔ #{e.message}"
        end
        puts "🌳 UID #{identifier} → DID #{tree.did}#{tree.previously_new_record? ? ' (Tree створено)' : ''}"
        tree.did
      else
        tree = Tree.find_by(did: identifier)
        if tree && tree.silicon_uid_hex.blank?
          abort "⛔ Tree #{identifier} без кремнієвого паспорта: post-FW.54 кремній оголосить " \
                "деривований DID, не цей. Передай 24-hex UID плати замість DID."
        end
        identifier
      end

    session = ProvisioningSession.create!(
      device_uid:       device_uid,
      batch_id:         args[:batch_id],
      gilka:            args[:gilka],
      operator_id:      Integer(args[:operator_id]),
      supervisor_id:    Integer(args[:supervisor_id]),
      firmware_version: args[:firmware_version],
      se_serial_hex: (args[:gilka] == "B" ? ENV["ATECC_SERIAL"] : nil),
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
    if outcome.se_transcript
      puts "   ATCA stmts:   #{outcome.se_transcript.statements.size}"
    end
  end
end
