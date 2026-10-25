provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = "voting"
    env        = var.env
    managed-by = "terraform"
  }
}

# Short-lived OAuth token of whoever runs Terraform (GitHub Actions via Workload Identity Federation).
data "google_client_config" "current" {}

provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.this.endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  }
}
