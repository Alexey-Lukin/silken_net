# SPDX-License-Identifier: AGPL-3.0-or-later
# ============================================================================
# Workload Identity Federation — keyless CI → GCP auth [INF.22]
# ============================================================================
# GitHub Actions mints a short-lived OIDC token per run; GCP STS exchanges it for
# an impersonated deploy-SA access token. This replaces the long-lived GCP_SA_KEY
# JSON in the deploy/drift workflows — a 6-place, boot-critical, never-expiring
# credential. [OPS.37] The one long-lived static-key exception (GCP_SA_KEY_BASE64 for
# an out-of-VPC Auth Proxy) is GONE with the platform that needed it — WIF is now
# exception-free, and no service-account key exists anywhere in this tree.
# (see docs/06_02 §Security Exception). This closes the CI→GCP leg only.
#
# Chicken-egg: this pool/provider/binding is created by the FIRST terraform apply,
# which the founder runs locally on their own ADC (DEPLOY-DAY Phase 0) — CI never
# runs the debut apply, so it needs no WIF yet. From the second apply on, CI is
# keyless. After the first apply, feed the two outputs
# (`workload_identity_provider` + `service_account_email`) into the GitHub repo
# VARIABLES GCP_WORKLOAD_IDENTITY_PROVIDER + GCP_SERVICE_ACCOUNT (non-secret
# identifiers — they also become the deploy-gate signal that replaced GCP_SA_KEY).

# WIF touches three APIs: iam.googleapis.com (pool/provider/binding CRUD — assumed
# pre-enabled, like every other IAM resource this root manages) + sts.googleapis.com (the OIDC→federated
# token exchange at auth time) + iamcredentials.googleapis.com (SA impersonation →
# access_token). sts + iamcredentials are NOT default-on. They are hit only at CI AUTH
# time (after apply), never during resource creation — but enable them here so the IaC
# is self-contained, else the FIRST keyless CI run (deploy + drift) dies on the auth
# step with SERVICE_DISABLED — a runtime failure that terraform validate and a local
# create-apply never surface. (No depends_on on the pool: pool CRUD rides iam.gapis,
# assumed pre-enabled like iam.tf's SA/binding resources; sts + iamcredentials are a
# runtime, not a create-time, dependency.)
resource "google_project_service" "sts" {
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials" {
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "silken-net-github"
  display_name              = "SilkenNet GitHub Actions"
  description               = "Keyless OIDC federation for CI deploy/drift workflows [INF.22]"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository.lowerAscii()"
    "attribute.repository_owner" = "assertion.repository_owner.lowerAscii()"
  }

  # Owner-scoped gate: WITHOUT attribute_condition the provider trusts ANY GitHub
  # repo's OIDC token — a critical wide-open door. lowerAscii() normalises the owner
  # case (the OIDC claim preserves GitHub's stored mixed case, e.g. "Alexey-Lukin";
  # the SA binding below matches the lowercased attribute). Defense-in-depth with the
  # repo-scoped principalSet on the binding.
  #
  # Ceiling [target INF.22]: this keys on the NAME claim (repository_owner), not the
  # immutable repository_owner_id. For a solo personal account the name-squatting
  # vector (owner deleted → someone re-registers "Alexey-Lukin" + "silken_net" →
  # inherits trust) is negligible; harden to numeric *_id if the repo ever changes hands.
  attribute_condition = "assertion.repository_owner.lowerAscii() == '${lower(split("/", var.github_repository)[0])}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Only workflows in var.github_repository may impersonate the deploy SA — repo-scoped,
# tighter than the owner-level provider condition. The principalSet matches the
# lowercased attribute.repository mapping above, so it is case-safe.
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${lower(var.github_repository)}"
}
