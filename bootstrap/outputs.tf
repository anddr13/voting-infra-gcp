output "workload_identity_provider" {
  description = "Full name of the Workload Identity provider for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account" {
  description = "Service account GitHub Actions impersonates."
  value       = google_service_account.github.email
}

output "next_steps" {
  description = "Commands that finish the setup."
  value       = <<-EOT
    gh variable set GCP_PROJECT_ID      --repo ${var.github_repo} --body "${var.project_id}"
    gh variable set GCP_WIF_PROVIDER    --repo ${var.github_repo} --body "${google_iam_workload_identity_pool_provider.github.name}"
    gh variable set GCP_SERVICE_ACCOUNT --repo ${var.github_repo} --body "${google_service_account.github.email}"
    git add infra/backend.hcl && git commit -m "Add backend config" && git push
  EOT
}
