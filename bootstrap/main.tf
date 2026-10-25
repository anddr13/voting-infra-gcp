# One-time setup, run from a laptop with local state after
# `gcloud auth application-default login` (see README):
#   - required APIs;
#   - GCS bucket for the main stack's state;
#   - Workload Identity Federation for GitHub Actions, so no service account key
#     is stored in GitHub.
# Costs ~$0 and is meant to stay; only infra/ is created and destroyed daily.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
  ])

  service = each.value
}

# --- Terraform state ------------------------------------------------------------

resource "google_storage_bucket" "state" {
  name                        = "${var.project_id}-voting-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.apis]
}

# --- GitHub Actions identity -------------------------------------------------------

resource "google_service_account" "github" {
  account_id   = "voting-infra-github"
  display_name = "GitHub Actions: ${var.github_repo}"

  depends_on = [google_project_service.apis]
}

# Broad on purpose for a sandbox project: the stack creates networks, GKE, service accounts
# and IAM bindings, and Helm installs cluster-wide RBAC.
resource "google_project_iam_member" "github" {
  for_each = toset([
    "roles/editor",
    "roles/container.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountUser",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github.email}"
}

# Deleted pools are kept for 30 days and their IDs cannot be reused meanwhile,
# which is one more reason not to destroy the bootstrap.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "voting-infra-gcp"
  display_name                       = "voting-infra-gcp"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only workflows running on main of this one repository.
  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# --- Wiring for infra/ ---------------------------------------------------------------

resource "local_file" "backend" {
  filename        = "${path.module}/../infra/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    bucket = "${google_storage_bucket.state.name}"
    prefix = "voting/${var.env}"
  EOT
}
