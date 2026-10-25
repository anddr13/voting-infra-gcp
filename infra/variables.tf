variable "project_id" {
  description = "GCP project ID (with billing enabled)."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "Zone of the cluster. A zonal cluster's management fee is covered by the GKE free tier."
  type        = string
  default     = "europe-central2-a"
}

variable "env" {
  description = "Environment name, part of every resource name."
  type        = string
  default     = "dev"
}

variable "machine_type" {
  description = "Node machine type (2 vCPU / 8 GiB)."
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "Number of nodes."
  type        = number
  default     = 2
}

variable "spot" {
  description = "Spot VMs are ~3x cheaper and can be reclaimed, which is fine for a sandbox."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Repository Argo CD syncs from."
  type        = string
  default     = "https://github.com/anddr13/voting-gitops.git"
}

variable "gitops_revision" {
  description = "Branch or tag of the GitOps repository."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version."
  type        = string
  default     = "2.0.7"
}
