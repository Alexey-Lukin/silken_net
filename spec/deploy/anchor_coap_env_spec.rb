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
#   • present: AR-encryption ×3 (production-wide guard), RAILS_MASTER_KEY (secret_key_base
#     via credentials), POSTGRES_PASSWORD + REDIS_URL (DB/enqueue);
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

  it "carries the coap boot-critical set (AR-encryption ×3 + master-key + DB/Redis — SEC.22)" do
    expect(coap_env_vars).to include(
      "RAILS_MASTER_KEY", "REDIS_URL", "POSTGRES_PASSWORD",
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
    )
  end

  it "omits PROVISIONING (coap-guard skips it) and the signing quintet (job-only)" do
    # Denylist = the current job-only signers + PROVISIONING (stable, E.2 key-split). A NEW
    # ORACLE_*_PRIVATE_KEY added to the quintet must be added here too (a derive-from-SDL form
    # would auto-cover it — kept explicit for now since the quintet is architecturally frozen).
    forbidden = %w[
      PROVISIONING_MASTER_KEY ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY
      ORACLE_CELO_PRIVATE_KEY ETHEREUM_ANCHOR_PRIVATE_KEY SOLANA_WALLET_KEYPAIR
    ]
    expect(coap_env_vars & forbidden).to be_empty
  end
end
