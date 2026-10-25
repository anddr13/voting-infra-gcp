locals {
  name = "voting-${var.env}"
}

resource "google_compute_network" "this" {
  name                    = local.name
  auto_create_subnetworks = false
}

# VPC-native cluster: pods and services get their own secondary ranges.
resource "google_compute_subnetwork" "nodes" {
  name          = "${local.name}-nodes"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = "10.30.0.0/20"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.31.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.32.0.0/20"
  }
}
