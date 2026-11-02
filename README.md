# voting-infra-gcp

GKE cluster for the multi-cloud [voting-app](https://github.com/anddr13/voting-app).
Created with one click, destroyed with one click, and destroyed automatically every night: this is a pay-per-hour sandbox.

Related: [voting-gitops](https://github.com/anddr13/voting-gitops) (what runs in the cluster) ·
[voting-infra-azure](https://github.com/anddr13/voting-infra-azure) · [voting-infra-aws](https://github.com/anddr13/voting-infra-aws)

## What gets created

```
bootstrap/   once, local state:  project APIs · GCS bucket for state · monthly budget with e-mail alerts
                                  Workload Identity Federation + service account for GitHub Actions
infra/       daily (apply/destroy):
  VPC + subnet with secondary ranges for pods/services (VPC-native)
  Dedicated node service account (instead of the Compute Engine default SA, which has Editor)
  Zonal GKE (Regular channel, Workload Identity) + node pool: 2 spot e2-standard-2 nodes
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/NLB, KEDA, Strimzi, CloudNativePG, Kafka, Redis, PostgreSQL, app)
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
terraform apply -var project_id=<your-project-id> -var billing_account=<billing-account-id>
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

## Results (measured 2026-11-02, PostgreSQL)

Zonal GKE in europe-central2, 2 spot e2-standard-2 nodes, voting-gitops `main` (PostgreSQL via CloudNativePG, Kafka,
Redis, KEDA), applied and destroyed by the GitHub Actions workflow. Load from
[`loadtest/exactly-once-cloud.sh`](https://github.com/anddr13/voting-app/blob/main/loadtest/exactly-once-cloud.sh):
k6 on a laptop in Ukraine at 200 votes/s for 3 minutes, and 40 s in **every worker process gets SIGKILL**
(through a `kubectl debug node` pod), so Kafka redelivers what they had not committed.

| Step | Time |
|---|---|
| `terraform apply` (VPC, GKE, node pool, Argo CD) | 9 min 26 s |
| Argo CD waves until the app answered on the load balancer | 3 min 31 s |
| **Bring-up total** | **12 min 57 s** |
| Drain (root Application, LoadBalancer Services, PVCs) | 58 s |
| `terraform destroy` | 9 min 26 s |
| **Tear-down total** | **10 min 24 s** |

| Time | Worker replicas (ready) | Consumer lag | Node CPU |
|---|---|---|---|
| start | 1 | 1,583 | 20% / 23% |
| +21 s | 4 (1) | 4,251 | 11% / 19% |
| +39 s | **6** (max = partitions) | 5,119 | 11% / 19% |
| +40 s | SIGKILL to all six workers | | |
| +59 s | 6 | 8,533 | 34% / **88%** |
| +1 min 46 s | 6 | **17,260** (peak) | 22% / 54% |
| end of load (+2 min 52 s) | 6 | 13,776 | 40% / 76% |
| +81 s after the load | 6 | **0** | 23% / 36% |
| a few minutes later | **1** | 0 | |

- **35,991** requests, 100% answered `202`, 0 failed; p95 **83.5 ms** (laptop → Warsaw).
- **Exactly once:** 35,991 votes of this run in PostgreSQL = 35,991 accepted; `votes` and `tallies` agree. The
  restarted workers skipped **194** redelivered votes (`worker_votes_total{outcome="duplicate"}`), none was counted twice.
- The highest lag and the slowest drain of the three clouds: e2 is the cheapest general-purpose family, with no fixed
  CPU platform, and one node reached 88% CPU under the load.
- After the destroy, `gcloud` found no cluster, VM, disk, forwarding rule or address in the project. Only the
  `default` network and its four firewall rules remain, which Google creates with the Compute API and does not charge for.
- On 2026-11-01, the very first apply in this project failed in `terraform init` with `iam.serviceAccounts.getAccessToken`
  denied: the Workload Identity binding was a minute old and had not propagated yet. A rerun of the same job passed
  with no change.

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  `kubeconfig_command` writes credentials to a separate file (`~/.kube/voting-<cloud>`), so `~/.kube/config`
  and its current context are never modified.
- **A budget as the last safety net.** The nightly destroy can fail or be delayed, and Kubernetes-created load
  balancers or disks can outlive a failed drain. The bootstrap adds a $10/month budget scoped to this project that
  e-mails the billing account's admins at 50% actual and 100% forecasted spend. It alerts, it does not stop anything.
- **`deletion_protection = false`.** The provider defaults to `true`, and `terraform destroy` of the cluster simply fails.
- **Zonal, not regional cluster.** The free tier covers the management fee of one zonal cluster, and a regional cluster
  would also triple the nodes (one set per zone).
- **Spot nodes.** On GKE they carry no taint by default, so the charts need no tolerations.
- **`scripts/drain-cluster.sh` runs before `destroy`.** Forwarding rules and firewall rules for LoadBalancer Services and
  PD disks for PVCs are created by Kubernetes. Once the cluster is gone they stay behind, keep costing money and block
  the VPC deletion. The script deletes the `root` Application (cascading), then any remaining LoadBalancer Services and PVCs.
- **The cascade can deadlock on KafkaTopic finalizers.** Only the Strimzi topic operator removes them, and it runs
  inside the Kafka cluster; if the cascade deletes the Kafka cluster first, the topics and `root` hang forever (it
  happened on AKS). The drain polls instead of waiting blindly and drops those finalizers once no Kafka is left.
- **No JSON keys:** GitHub Actions signs in through Workload Identity Federation, trusted only for `main` of this
  repository (`attribute_condition`).
- **Immutable GitHub OIDC subjects.** Repositories created after 2026-07-15 present
  `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...` instead of `repo:<owner>/<repo>:ref:...`, so a
  re-created repository with the same name cannot reuse the trust. `bootstrap/github.tf` looks the IDs up
  in the GitHub API and the pool provider condition uses them; the old name-only form would be rejected with `AADSTS700213`-style
  "no matching federated identity" errors.
- The roles of the Actions service account (Editor + IAM admin + container.admin) are a deliberate shortcut for a sandbox project.
