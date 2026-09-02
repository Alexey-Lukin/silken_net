# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# INF.17 / SEC.22 regression guard. The Ingress Anchor coap daemon (compute.tf systemd
# env-file heredoc) is a SECOND deploy surface for the coap boot contract, outside
# config/deploy.yml. SEC.22 wired the AR-encryption keys into the app deploy surfaces but
# missed this heredoc → the anchor daemon raised SecurityError [SEC.22] on first boot
# (active_record_encryption_keys_check is production-wide, no coap skip). This asserts the
# anchor coap.env carries exactly the coap boot contract:
#   • present: AR-encryption ×3 (production-wide guard), SECRET_KEY_BASE (the image ships no
#     credentials.yml.enc, so the RAILS_MASTER_KEY the template carried until 2026-09-02
#     decrypted nothing and the daemon would have died «Missing secret_key_base» at boot —
#     `active_storage.verifier` calls message_verifier in every Rails process; SEC.22 Phase-2),
#     POSTGRES_PASSWORD + REDIS_URL (DB/enqueue), and the three-line slot
#     switch DEPLOYMENT_SLOT · POSTGRES_DATABASE · REDIS_URL (OPS.37 — one daemon, one slot
#     at a time; a template without all three lines leaves the switch without a home);
#   • absent:  PROVISIONING_MASTER_KEY (master_key_strength_check skips coap_listener) and
#     the signing quintet (job-only) — a re-added crown-jewel would sit in the anchor's
#     plaintext /proc/environ for nothing.
RSpec.describe "Ingress Anchor coap.env (compute.tf)" do # rubocop:disable RSpec/DescribeClass
  subject(:coap_env_vars) do
    lines  = File.read(REPO_ROOT.join("terraform/compute.tf")).lines
    start  = lines.index { |l| l.include?("<< 'COAP_ENV'") } or raise "coap.env heredoc start not found"
    length = lines[(start + 1)..].index { |l| l.strip == "COAP_ENV" } or raise "coap.env heredoc end not found"
    lines[start + 1, length].filter_map { |l| l[/\A\s*([A-Z][A-Z0-9_]*)=/, 1] }
  end

  it "carries the coap boot-critical set (AR-encryption ×3 + SECRET_KEY_BASE + DB/Redis — SEC.22)" do
    expect(coap_env_vars).to include(
      "SECRET_KEY_BASE", "REDIS_URL", "POSTGRES_PASSWORD",
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
    )
  end

  # [OPS.37 ⚖️ 2026-09-02] ONE anchor daemon feeds ONE slot at a time (canopy until the first
  # production deploy); the slot is a three-line edit of coap.env + restart, never a second
  # publisher of UDP 5683. A missing line here = a switch with no home, and DEPLOYMENT_SLOT
  # absent falls back to `production` SILENTLY (config/deployment_slot.rb).
  it "carries the three-line intake slot switch (DEPLOYMENT_SLOT · POSTGRES_DATABASE · REDIS_URL — OPS.37)" do
    expect(coap_env_vars).to include("DEPLOYMENT_SLOT", "POSTGRES_DATABASE", "REDIS_URL")
  end

  it "omits PROVISIONING (coap-guard skips it), the signing quintet (job-only) and RAILS_MASTER_KEY (Phase-2)" do
    # Denylist = the current job-only signers + PROVISIONING (stable, E.2 key-split) +
    # RAILS_MASTER_KEY (SEC.22 Phase-2, 2026-09-02: decrypts nothing in a container, and a
    # re-added line is the runtime vault dependency the latch dissolves). A NEW
    # ORACLE_*_PRIVATE_KEY added to the quintet must be added here too (a derive-from-SDL form
    # would auto-cover it — kept explicit for now since the quintet is architecturally frozen).
    forbidden = %w[
      PROVISIONING_MASTER_KEY ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY
      ORACLE_CELO_PRIVATE_KEY ETHEREUM_ANCHOR_PRIVATE_KEY SOLANA_WALLET_KEYPAIR
      RAILS_MASTER_KEY
    ]
    expect(coap_env_vars & forbidden).to be_empty
  end
end
