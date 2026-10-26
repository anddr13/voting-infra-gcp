# voting-infra-gcp

GKE cluster for the multi-cloud [voting-app](https://github.com/anddr13/voting-app).
Created with one click, destroyed with one click, and destroyed automatically every night: this is a pay-per-hour sandbox.

Related: [voting-gitops](https://github.com/anddr13/voting-gitops) (what runs in the cluster) ·
[voting-infra-azure](https://github.com/anddr13/voting-infra-azure) · [voting-infra-aws](https://github.com/anddr13/voting-infra-aws)

## What gets created

```
bootstrap/   once, local state:  project APIs · GCS bucket for state
                                  Workload Identity Federation + service account for GitHub Actions
infra/       daily (apply/destroy):
  VPC + subnet with secondary ranges for pods/services (VPC-native)
  Dedicated node service account (instead of the Compute Engine default SA, which has Editor)
  Zonal GKE (Regular channel, Workload Identity) + node pool: 2 spot e2-standard-2 nodes
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/NLB, KEDA, Strimzi, Kafka, Redis, Mongo, app)
```

**Cost (approximate):** the zonal cluster management fee ($0.10/h) is covered by the GKE free tier,
2 spot nodes ~$0.05/h, load balancer, IPs and disks ~$0.04/h ≈ **$0.09/h**, i.e. ~$0.4 for a 4-hour session
or ~$2 per day. The cheapest of the three clouds.

## One-time bootstrap

Requires `gcloud` (`gcloud auth application-default login`), `terraform` ≥ 1.10 and `gh`.
Create the project in the console and link a billing account to it first.

```bash
cd bootstrap
terraform init
terraform apply -var project_id=<your-project-id>
terraform output -raw next_steps   # run the printed commands: repository variables + commit backend.hcl
```

Keep `bootstrap/` around: the GCS bucket holds the state, and a deleted Workload Identity pool keeps its name reserved for 30 days.

## Create / destroy

GitHub → **Actions → terraform → Run workflow**:
- `apply`: ~15–20 minutes (GKE ~6–8, Argo CD + Kafka ~8). The job waits until the app responds
  and writes its URL to the job summary.
- `destroy`: removes everything. Two nightly crons (01:23 and 03:53 UTC) run it in case you forget; they avoid the top of the hour,
  where GitHub delays scheduled runs (a 01:00 run once started at 05:42).

From a laptop (requires `gke-gcloud-auth-plugin`):

```bash
cd infra
terraform init -backend-config=backend.hcl
terraform apply -var project_id=<your-project-id>
eval "$(terraform output -raw kubeconfig_command)"   # separate kubeconfig file, ~/.kube/config stays untouched
```

## Things to look at once it is up

```bash
kubectl -n argocd get applications                     # waves: traefik/keda/strimzi → data → voting
kubectl -n voting get kafka,kafkatopic,pods
kubectl -n voting get scaledobject,hpa -w              # run the k6 test from voting-app in another terminal
kubectl -n argocd port-forward svc/argocd-server 8443:443
```

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  `kubeconfig_command` writes credentials to a separate file (`~/.kube/voting-<cloud>`), so `~/.kube/config`
  and its current context are never modified.
- **`deletion_protection = false`.** The provider defaults to `true`, and `terraform destroy` of the cluster simply fails.
- **Zonal, not regional cluster.** The free tier covers the management fee of one zonal cluster, and a regional cluster
  would also triple the nodes (one set per zone).
- **Spot nodes.** On GKE they carry no taint by default, so the charts need no tolerations.
- **`scripts/drain-cluster.sh` runs before `destroy`.** Forwarding rules and firewall rules for LoadBalancer Services and
  PD disks for PVCs are created by Kubernetes. Once the cluster is gone they stay behind, keep costing money and block
  the VPC deletion. The script deletes the `root` Application (cascading), then any remaining LoadBalancer Services and PVCs.
- **No JSON keys:** GitHub Actions signs in through Workload Identity Federation, trusted only for `main` of this
  repository (`attribute_condition`).
- **Immutable GitHub OIDC subjects.** Repositories created after 2026-07-15 present
  `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...` instead of `repo:<owner>/<repo>:ref:...`, so a
  re-created repository with the same name cannot reuse the trust. `bootstrap/github.tf` looks the IDs up
  in the GitHub API and the pool provider condition uses them; the old name-only form would be rejected with `AADSTS700213`-style
  "no matching federated identity" errors.
- The roles of the Actions service account (Editor + IAM admin + container.admin) are a deliberate shortcut for a sandbox project.
