# Dedicated node identity instead of the Compute Engine default service account (which is Editor).
resource "google_service_account" "nodes" {
  account_id   = "${local.name}-nodes"
  display_name = "GKE nodes of ${local.name}"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name       = local.name
  location   = var.zone
  network    = google_compute_network.this.id
  subnetwork = google_compute_subnetwork.nodes.id

  # Node pools are managed separately; GKE still insists on creating a default one first.
  remove_default_node_pool = true
  initial_node_count       = 1

  # The provider defaults to true, which would make `terraform destroy` fail.
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "this" {
  name       = var.spot ? "spot" : "standard"
  cluster    = google_container_cluster.this.name
  location   = var.zone
  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    spot            = var.spot
    disk_type       = "pd-balanced"
    disk_size_gb    = 30
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_project_iam_member.nodes]
}
