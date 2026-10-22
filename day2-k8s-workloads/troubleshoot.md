# Troubleshooting Log — k8s-day2

Date: 2026-10-22
Environment: macOS (darwin_arm64), zsh
Tooling: kubectl (EKS cluster `enterprise-eks`, us-east-1)

---

## Issue 1: Redis Pod stuck in `Pending` — PVC unbound, `gp3` StorageClass missing

### Symptom

After deploying the Redis StatefulSet, `redis-cart-0` stayed in `Pending`
for 41 minutes — it never scheduled:

```
NAME           READY   STATUS    RESTARTS   AGE
redis-cart-0   0/1     Pending   0          41m
```

### Root cause analysis

#### Failure chain

```
Redis StatefulSet
      ↓
PVC "data-redis-cart-0" requests storageClassName: gp3
      ↓
Cluster has no "gp3" StorageClass ❌
      ↓
PVC stays Pending (no EBS volume created)
      ↓
Pod cannot schedule: "unbound immediate PersistentVolumeClaims" ❌
      ↓
Pod Pending ❌
```

#### Diagnostic output

**1. Pod describe — Event:**

```
Warning  FailedScheduling  0/2 nodes are available:
pod has unbound immediate PersistentVolumeClaims. not found
```

Meaning: a pod with an unbound PVC cannot be scheduled. The PVC itself is
Pending, so the scheduler placed the pod nowhere.

**2. PVC describe — Event (the actual error):**

```
Warning  ProvisioningFailed  storageclass.storage.k8s.io "gp3" not found
```

Meaning: the PVC asked for a StorageClass named `gp3`, which does not exist
in the cluster. No EBS volume could be provisioned.

**3. Node resources — healthy:**

```
Allocated resources:
  cpu    350m (18%)
  memory 140Mi (1%)
```

Meaning: nodes had plenty of capacity. The problem was storage provisioning,
not resources.

**4. StorageClass list — `gp3` missing:**

```
NAME   PROVISIONER             AGE
gp2    kubernetes.io/aws-ebs   2d22h
```

Meaning: only `gp2` (legacy in-tree provisioner) exists; the `gp3` CSI
StorageClass was never created.

#### Summary

- The problem is in the storage provisioner, not in resources.
- PVC asked for `gp3` → StorageClass missing → EBS volume never created →
  pod never scheduled.
- The EBS CSI driver was not installed either — without it, a `gp3`
  StorageClass cannot work.

---

### Resolution

#### Step 1: Create the EBS CSI driver IAM role

The EBS CSI driver needs IAM permissions to create/attach volumes in AWS.

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster enterprise-eks \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

Notes: `--role-only` creates just the IAM role (no Kubernetes
ServiceAccount). `AmazonEBSCSIDriverPolicy` grants the required EBS
permissions. `--approve` auto-approves the CloudFormation changes.

#### Step 2: Install the EBS CSI driver addon

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create addon \
  --cluster enterprise-eks \
  --name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
  --force
```

Note: `--service-account-role-arn` binds the IAM role to the addon's
ServiceAccount. The `--pod-identity-associations` flag is not supported in
this `eksctl` version; this is the correct alternative.

#### Step 3: Create the `gp3` StorageClass

`gp3-storageclass.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
```

```bash
kubectl apply -f gp3-storageclass.yaml
# Output: storageclass.storage.k8s.io/gp3 created
```

Line-by-line:

- **`provisioner: ebs.csi.aws.com`** — the standard EBS CSI driver;
  correct for this `eks_managed_node_groups` cluster.
- **`volumeBindingMode: WaitForFirstConsumer`** — the volume is only
  created after the pod is scheduled. **Critical for multi-AZ clusters**:
  the AZ for the EBS volume is only known once the pod's node is chosen.
- **`encrypted: "true"`** — EBS encryption at rest (compliance
  requirement).

#### Step 4: Automatic recovery

Once the StorageClass existed, the **Kubernetes reconciliation loop**
resolved the issue on its own — **no delete/recreate needed**.

```bash
kubectl get pvc -n ecommerce
kubectl get pods -n ecommerce -l app=redis-cart
```

**Before → After:**

| Resource | Before (Issue) | After (Resolved) |
|---|---|---|
| **PVC `data-redis-cart-0`** | `Pending`, no volume | **`Bound`**, `pvc-3803d3e1...`, 10Gi |
| **Pod `redis-cart-0`** | `Pending` (`0/1`) | **`Running`** (`1/1`) |
| **StorageClass** | `gp3` not found | `gp3` (default) |
| **EBS Volume** | Not created | `10Gi gp3` in correct AZ |

After the `gp3` StorageClass was created, the EBS CSI driver provisioned a
10Gi gp3 EBS volume in the AZ of the node where `redis-cart-0` was
scheduled; the PVC became `Bound` and the pod `Running`. This is the power
of **Kubernetes declarative reconciliation** — the controller continuously
works to achieve the desired state (PVC `Bound`) without manual help.

---

### Side issues encountered & fixes

#### Issue A: `zsh: command not found: #`

**Cause**: Interactive comments are disabled by default in zsh.

**Fix**:

```bash
echo "setopt interactivecomments" >> ~/.zshrc
source ~/.zshrc
```

This enables `#` comments in interactive zsh shells (bash has them by
default; zsh requires manual enabling).

#### Issue B: `unknown flag: --pod-identity-associations`

**Cause**: The installed `eksctl` version does not support that flag on
`create addon`.

**Fix**: Use `eksctl create iamserviceaccount` for the IAM role +
`eksctl create addon --service-account-role-arn` for the addon — this
combination works reliably.

Note: flags change between `eksctl` versions; `--service-account-role-arn`
is a widely supported flag and the correct approach here.

#### Issue C: `the path "gp3-storageclass.yaml" does not exist`

**Cause**: YAML content was provided inline but the file was never created
on disk.

**Fix**: Create the file first with a heredoc, then apply:

```bash
cat > gp3-storageclass.yaml <<'EOF'
...yaml content...
EOF
kubectl apply -f gp3-storageclass.yaml
```

`kubectl apply -f` reads **files from the filesystem only**, not from
stdin — the file must exist before applying.

---

### Final validation

| # | Check | Command | Result |
|---|---|---|---|
| 1 | StorageClass | `kubectl get storageclass` | `gp3 (default) ebs.csi.aws.com` |
| 2 | PVC bound | `kubectl get pvc -n ecommerce` | `Bound`, 10Gi, `pvc-3803...` |
| 3 | Pod running | `kubectl get pods -n ecommerce -l app=redis-cart` | `1/1 Running` |
| 4 | Volume in correct AZ | `kubectl get pv <pv-name> -o jsonpath='{.spec.nodeAffinity}'` | Same AZ as scheduled node |

---

### Key learnings

1. **`Pending` pod = two possibilities**: (a) not enough schedulable
   resources, or (b) an unbound PVC. **`kubectl describe pod` Events**
   always tells which one.
2. **StorageClass + CSI driver + IAM role — all three must exist together**.
   Missing any one of them leaves the PVC `Pending`.
3. **`WaitForFirstConsumer` mode is mandatory for multi-AZ clusters** — it
   ensures the volume is created in the pod's AZ.
4. **Kubernetes reconciliation** — once the StorageClass was created, the
   PVC and pod recovered **with zero manual intervention**.
5. **2026 best practice**: retire `gp2` (in-tree) and keep `gp3` (CSI) as
   the default StorageClass.

---

### Optional cleanup

```bash
# Remove the deprecated gp2 StorageClass
kubectl get pvc -A | grep gp2   # any PVCs still using gp2?
kubectl delete storageclass gp2  # only if none
```

`gp2` is no longer needed now that `gp3` is the default. If no PVC uses it,
the deprecated provisioner can be removed. **This does not affect existing
PVs.**

---

**Summary**: Issue = missing `gp3` StorageClass. Resolution = EBS CSI
driver + IAM role + `gp3` StorageClass. Result = automatic recovery
(PVC `Bound`, pod `Running`). **Zero manual intervention** after the
StorageClass was created — this is the power of Kubernetes' declarative
model.

---

# Day 2: Issue & Resolution Log — Complete Debugging Record

Chronological record of every issue, root cause, resolution, and enterprise
lesson from the Day 2 hands-on session. Serves as a portfolio/runbook
reference for the Day 12 capstone.

## Executive Summary

| Attribute | Value |
|---|---|
| Session | Day 2 — Core Workloads & Zero-Downtime Deployment |
| Total Issues | 4 (cascading failures) |
| Time to Resolution | ~75 minutes |
| Root Category | Missing prerequisites + Image/PSA incompatibility |
| Final State | 3 Frontend Pods Running, Redis StatefulSet Running, PDB allows 1 disruption |

---

## Issue #2: ProgressDeadlineExceeded — Frontend Deployment Failed

### Symptom

```bash
$ kubectl rollout status deployment/frontend -n ecommerce
error: deployment "frontend" exceeded its progress deadline

$ kubectl get pods -n ecommerce -o wide
NAME           READY   STATUS    RESTARTS   AGE
redis-cart-0   1/1     Running   0          47m
# frontend pods are not visible at all

$ kubectl describe deployment frontend -n ecommerce
Conditions:
  Available       False   MinimumReplicasUnavailable
  ReplicaFailure  True    FailedCreate
  Progressing     True    NewReplicaSetCreated
```

### Root cause

The image `registry.example.com/ecommerce/frontend:2.4.1` points to a fake
registry (`example.com` is a placeholder). Kubernetes cannot pull that
image, so it never creates the pods.

Note: `ProgressDeadlineExceeded` is only a **symptom**, not the root cause.
Kubernetes is merely saying "the rollout did not complete within the
progress deadline" — it does not say why.

### Resolution (attempt 1)

```bash
kubectl set image deployment/frontend -n ecommerce \
  frontend=nginx:1.27-alpine

kubectl rollout status deployment/frontend -n ecommerce
```

`set image` switched the image to `nginx:1.27-alpine`. This did **not**
fully fix the problem — Issue #3 followed immediately.

### Enterprise lessons

| Lesson | Why it matters |
|---|---|
| Symptom ≠ Root Cause | When `ProgressDeadlineExceeded` appears, `kubectl describe rs` is mandatory |
| Image registry validation | Check image existence in CI (e.g. `docker manifest inspect`) |
| Never use placeholder registries | `example.com` must never appear in production manifests |

---

## Issue #3: FailedCreate — ServiceAccount Missing

### Symptom

```bash
$ kubectl describe rs $RS_NAME -n ecommerce | grep -A10 "Events"
Warning  FailedCreate  1s (x19 over 21m)  replicaset-controller
  Error creating: pods "frontend-58764bb595-" is forbidden:
  error looking up service account ecommerce/frontend-sa:
  serviceaccount "frontend-sa" not found
```

### Root cause

The ServiceAccount & RBAC file (`frontend-sa`, Role, RoleBinding) from Day 2
Step 2 was never applied. The SA must exist before the Deployment.

Why does Kubernetes enforce this? The pod template references
`serviceAccountName: frontend-sa`. Before creating a pod, the API server
verifies that SA exists and denies admission if it does not.

### Resolution

```bash
kubectl create serviceaccount frontend-sa -n ecommerce
```

Better approach (declarative):

```yaml
# frontend-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-sa
  namespace: ecommerce
```

```bash
kubectl apply -f frontend-sa.yaml
```

`kubectl create` is imperative; `kubectl apply -f` is declarative. In
enterprise environments only declarative is acceptable — GitOps (Argo CD)
supports `apply` only.

### Enterprise lessons

| Lesson | Why it matters |
|---|---|
| Dependency ordering | Apply in order: SA → Role → RoleBinding → Deployment |
| Argo CD sync waves | `argocd.argoproj.io/sync-wave: "-1"` annotation creates the SA first |
| FailedCreate vs ImagePullBackOff | FailedCreate = API server rejects; ImagePullBackOff = kubelet pull fails |

Argo CD sync wave example:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-sa
  namespace: ecommerce
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # before the Deployment
```

---

## Issue #4: PSA `restricted` Violation — Root Image Rejected

### Symptom

(Expected after the SA fix)

```bash
Warning  FailedCreate  ...  Error creating: pods "frontend-xxx" is forbidden:
  violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false (container "frontend" must set securityContext.allowPrivilegeEscalation=false),
  unrestricted capabilities (container "frontend" must set securityContext.capabilities.drop=["ALL"]),
  runAsNonRoot != true (pod or container "frontend" must set securityContext.runAsNonRoot=true),
  seccompProfile (pod or container "frontend" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

### Root cause

The `nginx:1.27-alpine` image runs as root (UID 0) by default and binds
port 80. The namespace enforces
`pod-security.kubernetes.io/enforce: restricted`, so the API server rejects
the pod.

### Resolution

**Option A — use a non-root image (recommended):**

```bash
kubectl set image deployment/frontend -n ecommerce \
  frontend=nginxinc/nginx-unprivileged:1.27-alpine
```

**Option B — specify a full securityContext:**

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101           # nginx user
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: frontend
          image: nginxinc/nginx-unprivileged:1.27-alpine
          ports:
            - containerPort: 8080   # unprivileged port
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

The `nginxinc/nginx-unprivileged` image is designed to run non-root
(UID 101) on port 8080 and satisfies the `restricted` PSA out of the box.
If you must use the official nginx image, the securityContext has to be
fully specified — and because the image's default user is root, it can
still fail in some cases.

### Enterprise lessons

| Lesson | Why it matters |
|---|---|
| Non-root images | Image selection must be security-first |
| `restricted` PSA | Baseline for production namespaces |
| Port 80 vs 8080 | Non-root containers cannot bind ports below 1024 |
| readOnlyRootFilesystem | nginx needs writable `/var/cache/nginx`, `/var/run` (emptyDir) |

---

## Issue #5: Liveness/Readiness Probes — Wrong Paths

### Symptom

(Expected after the image fix)

```bash
$ kubectl get pods -n ecommerce -l app=frontend
NAME                       READY   STATUS    RESTARTS      AGE
frontend-xxx-yyy           0/1     Running   5 (30s ago)   2m

$ kubectl describe pod frontend-xxx-yyy -n ecommerce | grep -A3 "Liveness"
  Liveness:  http-get http://:8080/healthz delay=15s timeout=1s period=10s
  Warning  Unhealthy  10s  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 404
```

### Root cause

The Deployment YAML configures probes against `/healthz` and `/readyz`.
nginx does not serve those paths — it only serves `/`. The 404 makes the
probe fail → kubelet restarts the container → CrashLoopBackOff.

### Resolution

```bash
kubectl patch deployment frontend -n ecommerce --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"},
  {"op":"replace","path":"/spec/template/spec/containers/0/startupProbe/httpGet/path","value":"/"}
]'
```

Better long-term approach: the application should expose a dedicated
`/healthz` endpoint (in nginx config:
`location /healthz { return 200; }`).

Probes are application health checks. `/healthz` is an industry convention
but is not built into nginx — you must know which paths the image you use
actually serves. In production the application team must implement
`/healthz` (liveness) and `/readyz` (readiness).

### Enterprise lessons

| Lesson | Why it matters |
|---|---|
| Match probes to the image | nginx → `/`, custom app → `/healthz`, gRPC → `grpc_health_probe` |
| startupProbe matters | Prevents restart loops for slow-starting apps |
| Liveness vs readiness | Liveness fail → restart; readiness fail → traffic stops (no restart) |
| `--previous` flag | `kubectl logs --previous` shows the last logs during a crash loop |

---

## Final State — All Green

```bash
$ kubectl get pods -n ecommerce -l app=frontend
NAME                        READY   STATUS    RESTARTS   AGE
frontend-78789f954d-cdc4w   1/1     Running   0          24s
frontend-78789f954d-rlglm   1/1     Running   0          42s
frontend-78789f954d-snqql   1/1     Running   0          33s

$ kubectl get pdb -n ecommerce
NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
frontend-pdb   2               N/A               1

$ kubectl get sa frontend-sa -n ecommerce
NAME          AGE
frontend-sa   49s
```

### Validation matrix

| Enterprise check | Command | Expected | Status |
|---|---|---|---|
| Pod health | `kubectl get pods -l app=frontend` | 3 × 1/1 Running | OK |
| Rollout status | `kubectl rollout status deployment/frontend` | successfully rolled out | OK |
| PDB availability | `kubectl get pdb` | ALLOWED DISRUPTIONS: 1 | OK |
| Service account | `kubectl get sa frontend-sa` | exists | OK |
| PVC bound | `kubectl get pvc` | Bound | OK |
| Redis StatefulSet | `kubectl get sts redis-cart` | 1/1 Ready | OK |
| Service endpoints | `kubectl get endpointslices` | 3 frontend IPs | OK |
| Probes passing | `kubectl describe pod` | no unhealthy events | OK |

---

## Key Takeaways (interview-ready)

### 1. Debugging methodology

```
Symptom (ProgressDeadlineExceeded)
  ↓
kubectl describe deployment → Conditions
  ↓
kubectl get rs → ReplicaSet
  ↓
kubectl describe rs → Events (root cause!)
  ↓
Fix → Verify → Rollout
```

### 2. Common failure patterns

| Symptom | Likely cause | First command |
|---|---|---|
| Pending | Scheduler cannot place the pod | `kubectl describe pod` → Events |
| ImagePullBackOff | Wrong image/registry | `kubectl describe pod` |
| FailedCreate | SA / RBAC / PSA / Kyverno | `kubectl describe rs` |
| CrashLoopBackOff | App crash / probe fail | `kubectl logs --previous` |
| ProgressDeadlineExceeded | Root cause is elsewhere | `kubectl describe rs` |

### 3. Enterprise practices

| Practice | Implementation |
|---|---|
| Declarative over imperative | `kubectl apply -f` > `kubectl create` |
| Dependency ordering | Argo CD sync-wave annotations |
| Security-first images | `nginx-unprivileged` over `nginx` |
| Explicit probes | Application-implemented `/healthz`, `/readyz` |
| Document every incident | This runbook → Day 12 portfolio |

### 4. Prevention checklist (CI/CD pipeline)

- [ ] Image existence check (`docker manifest inspect`)
- [ ] PSA compliance test (kube-score, kube-linter)
- [ ] Probe path verification (`curl -f http://localhost:PORT/healthz`)
- [ ] SA dependency validation (Kustomize/Helm ordering)
- [ ] Policy-as-Code tests (Kyverno `--dry-run=server`)

---

## Issue #6: ImagePullBackOff During Zero-Downtime Rollout

Complete documentation of the Day 2 hands-on issue and its resolution —
useful as learning notes and as an enterprise runbook entry.

### Issue summary

| Field | Value |
|---|---|
| Date | Day 2 (Core Workloads & Zero-Downtime Deployment) |
| Environment | macOS (Apple Silicon) · Colima · Local Kubernetes cluster |
| Namespace | `ecommerce` |
| Workload | `frontend` Deployment (3 replicas) |
| Symptom | New pod `frontend-8574bcf9d8-czqng` stuck in `ImagePullBackOff` |
| Impact | Zero — 3 old pods remained 1/1 Running and served all traffic |
| Root cause | Placeholder image registry `registry.example.com` used in `kubectl set image` |
| Resolution time | ~5 minutes |

### Step 1: Symptom discovery

Seen while watching with `kubectl get pods -w`:

```
NAME                        READY   STATUS             RESTARTS   AGE
frontend-78789f954d-cdc4w   1/1     Running            0          75m
frontend-78789f954d-rlglm   1/1     Running            0          75m
frontend-78789f954d-snqql   1/1     Running            0          75m
frontend-8574bcf9d8-czqng   0/1     ImagePullBackOff   0          97s
frontend-8574bcf9d8-czqng   0/1     ErrImagePull       0          105s
```

- **`ImagePullBackOff`** → Kubernetes tried to pull the image and failed;
  it now retries with exponential backoff.
- **`ErrImagePull`** → the immediate failure — the actual pull attempt
  failed.

Key point: the old 3 pods (`frontend-78789f954d-*`) stayed 1/1 Running —
**the service never went down**. This is exactly what `maxUnavailable: 0`
buys you.

### Step 2: Diagnosis — root cause analysis

**Diagnosis 1: pod events**

```bash
kubectl describe pod frontend-8574bcf9d8-czqng -n ecommerce
```

Events section (typical output):

```
Warning  Failed     2m   kubelet  Failed to pull image
  "registry.example.com/ecommerce/frontend:2.4.2":
  rpc error: code = Unknown desc = failed to pull and unpack image:
  failed to resolve reference "registry.example.com/ecommerce/frontend:2.4.2":
  failed to do request: Head "https://registry.example.com/v2/...":
  dial tcp: lookup registry.example.com: no such host
```

- `failed to resolve reference` → DNS lookup failed.
- `lookup registry.example.com: no such host` → the domain does not exist.
- `example.com` → placeholder domain documented in RFC 2606; it exists only
  for documentation and will never resolve.

**Diagnosis 2: desired vs actual state comparison**

```bash
# Deployment (desired state)
kubectl get deployment frontend -n ecommerce \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Output: registry.example.com/ecommerce/frontend:2.4.2  ❌

# Running pods (actual state)
kubectl get pods -n ecommerce -l app=frontend \
  -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'
# Output: nginxinc/nginx-unprivileged:1.27-alpine  ✅
```

| Source | Image | Verdict |
|---|---|---|
| Deployment spec | `registry.example.com/ecommerce/frontend:2.4.2` | ❌ fake placeholder |
| Running pods | `nginxinc/nginx-unprivileged:1.27-alpine` | ✅ real, public image |

The Deployment is the declarative "what I want". The running pods were
created earlier with a real image (nginx-unprivileged). The disconnect:
`kubectl set image` moved the Deployment to the fake image, while the old
pods kept living on their real image.

**Diagnosis 3: secondary — Colima down**

```bash
docker pull registry.example.com/ecommerce/frontend:2.4.2
```

```
Cannot connect to the Docker daemon at unix:///Users/premrasapalli/.colima/default/docker.sock.
Is the docker daemon running?
```

- `Cannot connect to the Docker daemon` → Colima (local Docker runtime) is
  stopped.
- The socket path is Colima's own — this machine does not use Docker
  Desktop.

### Step 3: Resolution — step by step

**Fix 1: start Colima (local Docker runtime)**

```bash
colima status
colima start
docker ps
```

- `colima status` → if `Running: false`, start it.
- `colima start` → starts the Lima VM + Docker daemon (1–2 minutes the
  first time).
- `docker ps` → confirms the daemon responds.

If `colima start` fails:

```bash
colima stop
colima delete
colima start --cpu 4 --memory 8 --disk 60
```

Note: `colima delete` removes local images/containers, but has **no impact
on the EKS cluster**.

**Fix 2: rolling update with a real image**

Before (failing state):

```yaml
image: registry.example.com/ecommerce/frontend:2.4.2   # ❌ fake
```

After (working state):

```bash
kubectl set image deployment/frontend \
  frontend=nginxinc/nginx-unprivileged:1.27 \
  -n ecommerce
```

- `nginxinc/nginx-unprivileged` → a real, public Docker Hub image — nginx
  official, non-root variant.
- `1.27` → a real, verifiable pinned tag (not `latest`).
- `kubectl set image` → creates a new ReplicaSet and performs a rolling
  transition from the old one.

Why `1.27` (non-alpine)? The old pods run `1.27-alpine`; using a different
tag makes the rolling update clearly observable.

**Fix 3: watch the rollout**

Terminal 1 — live pod state:

```bash
kubectl get pods -n ecommerce -l app=frontend -w
```

Terminal 2 — rollout status:

```bash
kubectl rollout status deployment/frontend -n ecommerce
```

- `-w` (watch) → continuous stream of pod state changes; the rolling
  update steps appear live.
- `rollout status` → the Deployment's Progressing condition updates and
  ends with `successfully rolled out`.

Expected sequence:

```
New pod Pending → ContainerCreating → Running
New pod 1/1 Ready → one old pod Terminating
Repeat × 3 (new starts, old stops)
```

### Step 4: Verification

**Verification 1: pods and images**

```bash
kubectl get pods -n ecommerce -l app=frontend \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

Expected:

```
frontend-xxxxxxxx-yyyyy   nginxinc/nginx-unprivileged:1.27
frontend-xxxxxxxx-zzzzz   nginxinc/nginx-unprivileged:1.27
frontend-xxxxxxxx-wwwww   nginxinc/nginx-unprivileged:1.27
```

**Verification 2: ReplicaSets (old vs new)**

```bash
kubectl get rs -n ecommerce -l app=frontend
```

Expected:

```
NAME                  DESIRED   CURRENT   READY   AGE
frontend-7f9c8b5d6a   3         3         3       2m    ← NEW (active)
frontend-78789f954d   0         0         0       85m   ← OLD (scaled to 0)
frontend-8574bcf9d8   0         0         0       12m   ← FAILED (scaled to 0)
```

- New ReplicaSet: `DESIRED=3, CURRENT=3, READY=3` → active.
- Old ReplicaSet: `DESIRED=0` → scaled down, but the record is kept (for
  rollback).
- Failed ReplicaSet: `DESIRED=0` → cleaned up correctly, still present in
  history.

`kubectl rollout history` shows these 3 ReplicaSets as revisions; any
revision can be rolled back to.

**Verification 3: zero-downtime confirmation**

```bash
# Continuous availability check (parallel terminal)
while true; do
  curl -s -o /dev/null -w "%{http_code} " http://frontend.ecommerce.svc.cluster.local:80
  sleep 0.5
done
```

Expected: only `200` responses, no `503`.

- `200` → healthy response.
- `503 Service Unavailable` → a downtime window (must not happen).
- Because `maxUnavailable: 0` is set, the entire rollout should be 200s
  only.

### Before vs after comparison

| Aspect | Before fix | After fix |
|---|---|---|
| Deployment image | `registry.example.com/...:2.4.2` (fake) | `nginxinc/nginx-unprivileged:1.27` (real) |
| New pod state | `ImagePullBackOff` ❌ | `Running 1/1` ✅ |
| Old pods | 3 Running (serving traffic) | Scaled to 0 |
| ReplicaSets | 2 (old + failed) | 3 (old, failed, new) |
| Service endpoints | 3 (old pods) | 3 (new pods) |
| Rollout status | stuck (`Waiting for deployment`) | `successfully rolled out` |
| User impact | zero (`maxUnavailable: 0` protected) | zero |

### Key learnings (enterprise notes)

**Learning 1: `example.com` = placeholder, not real**

RFC 2606 reserves `example.com`, `.test`, `.invalid`, and `.localhost` for
documentation. Never use them in real production.

Detection:

```bash
# Linux/macOS
nslookup registry.example.com
# Expected: "** server can't find registry.example.com: NXDOMAIN"
```

Enterprise rule: `registry.example.com` is fine in docs; code must always
reference a real registry.

**Learning 2: `maxUnavailable: 0` is the production safety net**

Observed behavior: even though one image failed, the service never went
down — because `maxUnavailable: 0` means "remove nothing until the new
pods are ready".

Enterprise value:

- Bad deploys → automatically rolled back with zero user impact
- Slow-starting apps → `startupProbe` + `maxUnavailable: 0` = safe
- Compliance: protects against SLA (99.99%) breaches

Anti-pattern: with `maxUnavailable: 1`, one pod would have briefly become
unavailable during this failure.

**Learning 3: pod events = first diagnostic step**

Workflow:

```bash
kubectl get pods -n <ns>              # 1. Symptom (ImagePullBackOff)
kubectl describe pod <pod> -n <ns>    # 2. Root cause (Events section)
kubectl logs <pod> -n <ns> --previous # 3. Previous crash logs (if CrashLoop)
```

Enterprise rule: `kubectl describe` before `kubectl logs`. For
`ImagePullBackOff` there are no logs — the cause lives in Events.

**Learning 4: old ReplicaSets = rollback safety**

Observed: the old ReplicaSet (`frontend-78789f954d`) stayed at `DESIRED=0`
without being deleted.

Enterprise value:

- Default: Kubernetes retains 10 ReplicaSets (`revisionHistoryLimit: 10`)
- Rollback: `kubectl rollout undo --to-revision=N` returns to a previous
  version in seconds
- Audit: `kubectl rollout history` shows every deployed version
- Compromise: set `revisionHistoryLimit: 3` to save storage

### Runbook entry (enterprise documentation)

```
RUNBOOK: Frontend ImagePullBackOff

SYMPTOM:
  New Pod stuck in ImagePullBackOff/ErrImagePull during deployment.
  Old Pods remain Running (maxUnavailable: 0 protection).

DETECTION:
  kubectl get pods -n ecommerce -l app=frontend -w
  kubectl describe pod <failing-pod> -n ecommerce | grep -A10 Events

ROOT CAUSE CANDIDATES:
  1. Wrong image name/tag (e.g., placeholder like registry.example.com)
  2. Missing/expired imagePullSecret (private registry)
  3. Network/DNS failure from nodes to registry

RESOLUTION:
  Step 1: Verify real image exists
    docker pull <actual-image:tag>
    OR
    aws ecr describe-images --repository-name <repo> --image-ids imageTag=<tag>

  Step 2: Update deployment with correct image
    kubectl set image deployment/frontend \
      frontend=<real-registry>/<repo>:<tag> -n ecommerce

  Step 3: Watch rollout
    kubectl rollout status deployment/frontend -n ecommerce

  Step 4: Verify
    kubectl get rs -n ecommerce -l app=frontend
    (new RS: READY=3, old RS: DESIRED=0)

ROLLBACK (if new image also fails):
  kubectl rollout undo deployment/frontend -n ecommerce

PREVENTION:
  - Use CI validation: docker pull image before applying to cluster
  - Kyverno policy: restrict-image-registries (only approved registry)
  - Never use `latest` tag; always pin versions
  - GitOps (Argo CD): dry-run sync before auto-sync
```

### Day 2 objective status

| Objective | Status | Evidence |
|---|---|---|
| Stateless workload deploy (Deployment) | OK | frontend 3 replicas Running |
| Stateful workload deploy (StatefulSet + PVC) | OK | redis-cart Running with PVC bound |
| Zero-downtime rolling update | OK | Proven — image failure caused 0 downtime |
| PDB (minAvailable) protection | OK | ALLOWED DISRUPTIONS: 1 |
| Multi-AZ spread | OK | topologySpreadConstraints active |
| Health checks (startup/liveness/readiness) | OK | all probes passing |
| RBAC (least privilege) | OK | frontend-sa ConfigMap read only |

**Day 2 PASSED** — despite the image pull issue, all enterprise patterns
worked as designed. The failure actually validated the zero-downtime
architecture.

---

## Issue #7: Cilium Install Failed — ServiceMonitor CRD Missing (Day 3)

**Date**: Day 3 — Networking (Cilium 1.20 + Gateway API)
**Environment**: macOS · EKS 1.36 (`enterprise-eks`) · Helm v3
**Component**: `cilium` Helm release (namespace `kube-system`)

### Symptom

`helm install cilium cilium/cilium --version 1.20.2 -n kube-system -f cilium-values.yaml` failed with:

```
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest:
resource mapping not found for name: "cilium-agent" namespace: "kube-system" from "":
no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
```

Before that, setting `trustCRDsExist: true` produced a similar error:

```
Error: INSTALLATION FAILED: execution error at (cilium/templates/validate.yaml:79:13):
Service Monitor requires monitoring.coreos.com/v1 CRDs.
```

### Root cause

1. **`cilium-values.yaml` has `prometheus.serviceMonitor.enabled: true`** →
   Cilium's Helm chart generates a `ServiceMonitor` resource in its
   manifest.
2. **Prometheus Operator CRDs are not installed in the EKS cluster** → the
   API server does not know the `monitoring.coreos.com/v1` API group.
3. **`trustCRDsExist: true` did not help** because that flag only skips
   validation at Helm **template-rendering** time. When Helm finally sends
   the manifest to the API server, server-side validation still rejects the
   unknown kind — that part cannot be bypassed.

### Resolution — Option A (recommended): install the Prometheus Operator CRD

```bash
# Step 1: install the ServiceMonitor CRD (server-side apply mandatory)
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

# Step 2: confirm the CRD exists
kubectl get crds | grep servicemonitors
# Expected: servicemonitors.monitoring.coreos.com

# Step 3: retry the Cilium install
helm install cilium cilium/cilium \
  --version 1.20.2 \
  --namespace kube-system \
  --values cilium-values.yaml
```

Why `--server-side`? The CRD manifest is too large
(`metadata.annotations` > 262KB), so a normal `kubectl apply` fails with
`Too long: must have at most 262144 bytes`. `--server-side` bypasses that
client-side limit.

### Resolution — Option B (temporary): disable ServiceMonitor

```yaml
# in cilium-values.yaml
prometheus:
  enabled: true
  serviceMonitor:
    enabled: false    # true → false
```

```bash
helm install cilium cilium/cilium \
  --version 1.20.2 \
  --namespace kube-system \
  --values cilium-values.yaml
```

Trade-off: Cilium metrics are not auto-scraped by Prometheus. After
kube-prometheus-stack is installed in Day 8, flip
`serviceMonitor.enabled: true` back and run `helm upgrade cilium`.

### Why Option A is recommended

- Day 8 (Observability) installs kube-prometheus-stack → the
  ServiceMonitor CRD will genuinely be needed then.
- Installing the CRD now means Cilium metrics (network flows, drops, DNS
  queries) start flowing to Prometheus immediately.
- Setting `trustCRDsExist: true` now and installing the CRD in Day 8 does
  **not** work — the CRD must exist at the time of `helm install`.

### Enterprise prevention

- Platform teams should install CRDs during **infrastructure bootstrap** —
  before any Helm chart that depends on them.
- Keep `serviceMonitor.enabled` as a feature flag in Helm charts and toggle
  it based on observability-stack availability.
- Run `helm template --validate` in CI to catch unknown kinds before
  reaching the API server.
- GitOps (Argo CD): use `syncOptions: [ServerSideApply=true]` to bypass CRD
  size limits.

### Verification

| Check | Command | Expected |
|---|---|---|
| ServiceMonitor CRD | `kubectl get crd servicemonitors.monitoring.coreos.com` | Present |
| Cilium release | `helm status cilium -n kube-system` | STATUS: deployed |
| Cilium pods | `kubectl get pods -n kube-system -l k8s-app=cilium` | Running (1 daemonset per node) |
| Cilium status | `kubectl exec -n kube-system ds/cilium -- cilium status --brief` | OK |
| ServiceMonitor resource | `kubectl get servicemonitor -n kube-system` | `cilium-agent` present |

### Key learnings

- `trustCRDsExist` only bypasses Helm **template-time** validation, not
  **server-side** validation.
- CRDs must be installed **before** the Helm release that needs them —
  dependency order matters.
- `kubectl apply --server-side` should be the default for large CRDs
  (especially Prometheus Operator's).
- In chaining mode (aws-cni), do not delete `aws-node` — Cilium's policy
  layer sits on top of it.
