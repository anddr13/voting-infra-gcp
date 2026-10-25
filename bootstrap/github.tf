# GitHub repositories created after 2026-07-15 present an immutable OIDC subject that carries
# the owner and repository IDs: repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>.
# A deleted and re-created repository with the same name gets a new ID, so it cannot take over
# this identity. The IDs are looked up here instead of being hard-coded; on GCP the pool
# provider matches the repository_id claim directly.
data "http" "github_repo" {
  url             = "https://api.github.com/repos/${var.github_repo}"
  request_headers = { Accept = "application/vnd.github+json" }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub repository ${var.github_repo} not found: create and push it before running bootstrap."
    }
  }
}

locals {
  github_repo = jsondecode(data.http.github_repo.response_body)
}
