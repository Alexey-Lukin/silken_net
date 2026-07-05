# =============================================================================
# [OPS.11] FinOps guard №1 — GCP billing budget with email thresholds.
#
# Why: disk_autoresize + egress can silently grow a bill charged to a personal
# card; without a budget there is NO signal at all. Thresholds fire e-mails to
# the Billing Account Administrators/Users (default IAM recipients — the solo
# founder IS the billing admin), no notification-channel plumbing needed.
#
# Guarded by billing_account_id (same count-pattern as allow_ssh): while the
# var is empty the whole block is a no-op, so CI applies stay clean until the
# founder provisions the value. ⚠️ Once set locally, the SAME value must reach
# CI (GitHub secret GCP_BILLING_ACCOUNT_ID → TF_VAR_billing_account_id, wired
# in deploy.yml / deploy-production.yml) — otherwise the next CI apply sees
# count=0 and DESTROYS the budget.
#
# ⚠️ REQUIRED (not optional): the CI service account needs a billing-account role
# BEFORE activation — terraform refreshes the budget on EVERY plan, and
# billing.budgets.get lives on the billing account, not the project (a one-off
# founder-auth apply does NOT help: the next CI plan 403s and, via
# `needs: terraform`, blocks every deploy). One-time grant:
#   gcloud billing accounts add-iam-policy-binding <ACCT_ID> \
#     --member="serviceAccount:silken-net-deploy@<project>.iam.gserviceaccount.com" \
#     --role="roles/billing.costsManager"
# Also note: billingbudgets API enablement is eventually-consistent — the very
# first activation apply may fail once; re-apply succeeds.
# =============================================================================

resource "google_project_service" "billingbudgets" {
  count              = var.billing_account_id != "" ? 1 : 0
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

data "google_project" "current" {
  count = var.billing_account_id != "" ? 1 : 0
}

resource "google_billing_budget" "monthly" {
  count           = var.billing_account_id != "" ? 1 : 0
  billing_account = var.billing_account_id
  display_name    = "silken-net-monthly"

  # Scope to this project only (budget_filter wants the project NUMBER, not id).
  budget_filter {
    projects = ["projects/${data.google_project.current[0].number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.billing_budget_usd)
    }
  }

  # 50 / 90 / 100% actual + forecasted-100% (fires BEFORE the money is spent).
  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.billingbudgets]
}
