output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "zone" {
  description = "Zone of the cluster."
  value       = google_container_cluster.this.location
}

output "kubeconfig_command" {
  description = "eval \"$(terraform output -raw kubeconfig_command)\": kubectl access through a separate kubeconfig file; ~/.kube/config is not touched. Needs gke-gcloud-auth-plugin."
  value       = "export KUBECONFIG=\"$HOME/.kube/voting-gcp\" && gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${google_container_cluster.this.location} --project ${var.project_id}"
}

output "argocd_ui" {
  description = "Argo CD UI via port-forward; the admin password is in the argocd-initial-admin-secret."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8443:443"
}
