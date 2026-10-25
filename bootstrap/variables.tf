variable "project_id" {
  description = "GCP project ID (create it and link billing in the console first)."
  type        = string
}

variable "region" {
  description = "Location of the state bucket."
  type        = string
  default     = "europe-central2"
}

variable "env" {
  description = "Environment name, used in the state prefix."
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "owner/name of the repository whose workflows may impersonate the service account."
  type        = string
  default     = "anddr13/voting-infra-gcp"
}
