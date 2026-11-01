variable "project_id" {
  description = "GCP project ID (create it and link billing in the console first)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID linked to the project (gcloud billing accounts list)."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget for the project; alerts at 50% actual and 100% forecasted spend."
  type        = number
  default     = 10
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
