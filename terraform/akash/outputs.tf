# =============================================================================
# Outputs — Akash Deployment Information
# =============================================================================
# Mirrors the structure of terraform/outputs.tf for consistency.
# See docs/DEPLOYMENT.md § "Akash Network" for the full deployment flow.

output "sdl_file" {
  description = "Path to the generated Akash SDL file (contains secrets — handle securely)"
  value       = local_file.akash_sdl.filename
}

output "sdl_hash" {
  description = "SHA-256 hash of the generated SDL (used to detect changes)"
  value       = sha256(local_file.akash_sdl.content)
}

output "deployment_note" {
  description = "Next steps after terraform apply"
  value       = <<-EOT
    Akash deployment initiated. Next steps:
    1. Check deployment status:  akash query deployment list --owner <your-address>
    2. View bids from providers: akash query market bid list --owner <your-address>
    3. Accept a bid:             akash tx market lease create --dseq <DSEQ> --provider <provider> --from ${var.akash_key_name}
    4. Send manifest:            akash provider send-manifest ${local_file.akash_sdl.filename} --dseq <DSEQ> --provider <provider> --from ${var.akash_key_name}
    5. Check service status:     akash provider lease-status --dseq <DSEQ> --provider <provider> --from ${var.akash_key_name}
    6. View logs:                akash provider lease-logs --dseq <DSEQ> --provider <provider> --from ${var.akash_key_name}
  EOT
}
