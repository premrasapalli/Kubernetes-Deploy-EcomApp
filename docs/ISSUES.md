# Issues Log

Every real failure gets an entry here. This is the most important learning artifact
in the repo: interviewers and future-you will read this.

## Rules

1. One issue per problem. IDs are sequential and never reused.
2. Never write "fixed" without a root cause.
3. The **Why this only works** section is mandatory. It must explain the dependency
   or invariant that made the fix correct — not just what command was run.
4. Paste real output (logs, `kubectl describe`, events, Hubble). Redact secrets.
5. Add a link from the relevant phase doc / commit message (`Fixes Issue #N`).

## Issue index

| # | Name | Phase | Status |
|---|---|---|---|
| 1 | Terraform EKS module v21.29 renamed inputs | 2 | Resolved |
| 2 | `kustomize` binary missing (kubectl bundles it) | 4 | Resolved |
| 3 | HTTPRoute targeted containerPort instead of Service port | 5 | Resolved (pre-apply review) |
| 4 | Helm silently ignored unknown Cilium values | 3 | Resolved (pre-apply review) |
| 5 | Cilium on EKS: no PodCIDR and no VXLAN SG rules | 3 | Resolved |
| 6 | EKS control plane cannot reach Cilium overlay pod IPs | 3 | Resolved with hostNetwork/workaround |

---

## Issue Template (copy this block)

```markdown
## Issue #<N>: <Short descriptive name>

### Environment
- Cluster: AWS EKS <version>
- CNI: Cilium <version>
- Date: <YYYY-MM-DD>
- Context: <what step we were doing>

### Symptom
<Exact errors / kubectl output / HTTP status. Redact secrets.>

### Root cause
<The technical reason. Be specific: which component, which config, which dependency.>

### Investigation
<Commands run and what they revealed. Include dead ends that looked plausible.>

### Resolution
<Exact commands / manifest diffs applied, in order.>

### Why this only works
<Explain the invariant/dependency. E.g. "Cilium Gateway API is implemented by the
Cilium L7 proxy, which requires kube-proxy replacement; without it the GatewayClass
is never accepted and no dataplane programs the Gateway.">

### Verification
<Proof of a healthy state: kubectl output, curl result, Hubble verdict.>

### Prevention
<Guardrail: validation script, preflight check, policy, or doc note.>
```

---

## Worked example (reference only — not a real issue in this project)

## Issue #0: Gateway API not programmed — Cilium requires kube-proxy replacement

### Environment
- Cluster: AWS EKS 1.36
- CNI: Cilium 1.20.2
- Date: 2026-10-22
- Context: First Gateway API deployment

### Symptom
```text
$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED
cilium   io.cilium/gateway-controller   Unknown

$ kubectl get gateway -n retailx
NAME                CLASS    ADDRESS   PROGRAMMED
retailx-gateway     cilium             Unknown
```

### Root cause
Cilium was installed in AWS-CNI chaining mode with `kubeProxyReplacement: "false"`.
Cilium Gateway API is implemented by the Cilium L7 proxy and requires kube-proxy
replacement. Operator log: `Gateway API support requires kube-proxy-replacement enabled`.

### Investigation
- `kubectl -n kube-system logs deploy/cilium-operator` -> explicit warning.
- `kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.kube-proxy-replacement}'` -> `false`.
- `kubectl -n kube-system get ds` -> `aws-node` + `kube-proxy` present.

### Resolution
- Rebuilt cluster with Cilium as primary CNI (no `vpc-cni`, no `kube-proxy`).
- Installed Cilium with `kubeProxyReplacement=true`, `k8sServiceHost`, `k8sServicePort`.
- Installed Gateway API v1.5.x experimental CRDs.
- Enabled `gatewayAPI`, `l2announcements`, `externalIPs`, LB IPAM pool.

### Why this only works
Gateway API in Cilium is not a separate controller that can run in chaining mode:
the Envoy dataplane is programmed through Cilium's eBPF service load-balancing path.
That path only exists when Cilium owns service routing (`kubeProxyReplacement=true`).
In chaining mode the kubelet/aws-cni/kube-proxy own pod and service networking, so
Cilium cannot program the VIP and the GatewayClass remains `Unknown` by design.

### Verification
```text
GatewayClass ACCEPTED=True
Gateway PROGRAMMED=True ADDRESS=10.0.3.250
HTTPRoute Accepted=True ResolvedRefs=True
curl /       -> 200, server: envoy
curl /admin  -> 403, server: envoy
```

### Prevention
- Preflight check: fail install if `kube-proxy-replacement != true`.
- Pin Gateway API CRDs to the version Cilium validates (experimental channel).
- Document chaining mode as unsupported for Gateway API.

---

## Issue #1: Terraform EKS module v21.29 renamed inputs

### Environment
- Cluster: AWS EKS 1.36 (not yet applied)
- CNI: Cilium 1.20.2 (planned)
- Date: 2026-10-23
- Context: Phase 2 — first `terraform validate`

### Symptom
```text
Error: Unsupported argument
  on eks.tf line 19, in module "eks":
  19:   bootstrap_self_managed_addons = false
An argument named "bootstrap_self_managed_addons" is not expected here.

Error: Unsupported argument
  on eks.tf line 25, in module "eks":
  25:   cluster_addons = { ... }
An argument named "cluster_addons" is not expected here.

Error: Unsupported argument
  on eks.tf line 17, in module "eks":
  17:   cluster_endpoint_public_access_cidrs = ...
An argument named "cluster_endpoint_public_access_cidrs" is not expected here.
```

### Root cause
The module constraint `version = "~> 21.0"` resolved to **v21.29.0**, whose input
surface was renamed:

| Old input (v20/early v21) | v21.29 input |
|---|---|
| `cluster_name` | `name` |
| `cluster_version` | `kubernetes_version` |
| `cluster_endpoint_public_access` | `endpoint_public_access` |
| `cluster_endpoint_public_access_cidrs` | `endpoint_public_access_cidrs` |
| `cluster_addons` | `addons` |
| `bootstrap_self_managed_addons` | removed — hardcoded `false` in v21 |

`bootstrap_self_managed_addons` is ignored/hardcoded to `false` by the v21 module
(see `docs/UPGRADE-21.0.md` in the module), which is exactly what Cilium-only
clusters need: no `aws-node`, no `kube-proxy`.

### Investigation
- `cat .terraform/modules/modules.json` -> module version `21.29.0`.
- `grep '^variable' .terraform/modules/eks/variables.tf` -> `name`, `kubernetes_version`, `addons`, `endpoint_public_access`.
- `grep bootstrap_self_managed_addons .terraform/modules/eks/main.tf` -> line 46 hardcodes `false`.
- `terraform validate` initially also flagged `cluster_endpoint_public_access_cidrs`.

### Resolution
Rewrote `01-terraform-eks/eks.tf` to the v21.29 input names and removed
`bootstrap_self_managed_addons` (the module owns that behaviour now):

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  addons = {
    coredns            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true, service_account_role_arn = aws_iam_role.ebs_csi.arn }
  }
}
```

### Why this only works
Terraform validates module inputs against the exact module version selected by
the lock/constraint. `~> 21.0` allows every `21.x` release, and v21.29.0 removed
the `cluster_*` aliases; there is no compatibility shim, so only the new names
validate. `bootstrap_self_managed_addons` cannot be "fixed" with a value because
the module hardcodes it to `false` — that is required here: installing `vpc-cni`
would put Cilium back into chaining mode and break Gateway API (Issue #0).

### Verification
```text
terraform validate -> Success! The configuration is valid.
terraform plan -var node_desired_size=0 -> saved plan (no schema errors)
```

### Prevention
- Pin the module to an exact version (`= 21.29.0`) or read `docs/UPGRADE-*.md`
  before widening constraints.
- Run `terraform validate` in CI on every change.
- Keep `terraform providers lock` / `.terraform.lock.hcl` committed.

---

## Issue #2: `kustomize` binary missing — kubectl already bundles it

### Environment
- macOS (darwin/arm64), kubectl v1.35.0
- Date: 2026-10-23
- Context: Phase 4 — rendering manifests before deploy

### Symptom
```text
zsh:1: command not found: kustomize
```

### Root cause
`kubectl` embeds Kustomize (v5.7.1 in this client), but no standalone
`kustomize` binary was on `PATH`. The scripts called `kustomize build`.

### Investigation
```bash
kubectl version --client      # Kustomize Version: v5.7.1
command -v kustomize          # not found
kubectl kustomize 03-k8s-manifests/overlays/dev | wc -l   # works
```

### Resolution
- Replaced `kustomize build ...` with `kubectl kustomize ...` in
  `05-scripts/03-deploy-app.sh`.
- Removed `kustomize` from the `00-preflight.sh` required-tools list.
- Kept `kubectl delete -k` in teardown (same embedded engine).

### Why this only works
`kubectl kustomize` runs the identical Kustomize engine that is compiled into the
matching kubectl, so no second binary and no client/plugin version skew is
possible. Installing a random standalone `kustomize` could silently differ from
the version kubectl uses for `delete -k`.

### Verification
```text
kubectl kustomize 03-k8s-manifests/overlays/dev -> 45 resources, 1312 lines
```

### Prevention
- Standardise on `kubectl kustomize` in all scripts.
- Preflight checks only binaries we actually invoke.

---

## Issue #3: HTTPRoute targeted a containerPort instead of a Service port

### Environment
- Cluster: EKS 1.36 + Cilium 1.20.2 (Gateway API)
- Date: 2026-10-23
- Context: Phase 5 — manifest review before first deploy

### Symptom
Reviewing `04-platform/gateway-api/httproute.yaml` before apply:

```yaml
- matches:
    - path: { type: PathPrefix, value: / }
  backendRefs:
    - name: frontend
      port: 8080        # containerPort, not the Service port
```

The frontend Service exposes `port: 80` -> `targetPort: http (8080)`.

### Root cause
Gateway API `backendRefs[].port` refers to the **Service** port, not the pod's
`containerPort`. The value `8080` was copied from `frontend.yaml`
(`containerPort: 8080`), so the Gateway would resolve `frontend:8080` and get
`connection refused` / `503` because no Service port 8080 exists.

### Investigation
```bash
kubectl kustomize 03-k8s-manifests/overlays/dev | grep -A8 'name: frontend' # Service ports
# port: 80, targetPort: http
grep -n 'port:' 04-platform/gateway-api/httproute.yaml
# frontend backendRef: 8080  <- mismatch
```

### Resolution
Changed the frontend `backendRefs[].port` to `80`:

```yaml
backendRefs:
  - name: frontend
    port: 80
```

### Why this only works
Traffic from Envoy goes to `<service>.<ns>.svc:<port>`. kube-proxy/Cilium
translates a **Service port** to the pod's `targetPort`; it never looks at
`containerPort` directly. `80` is the only port the frontend Service publishes,
so only `80` can be resolved. The other three backends were already correct
because their Service ports equal their container ports (8081–8083).

### Verification
After deploy:
```text
Gateway -> / -> 200 (server: envoy)
kubectl get httproute retailx-route -o jsonpath='{.status.parents[0].conditions}'
# Accepted=True, ResolvedRefs=True
```

### Prevention
- Rule: `backendRefs.port` must always equal a `Service.spec.ports[].port`.
- Add a CI check that renders Kustomize and cross-references HTTPRoute backend
  ports against Service ports.
- When Service port != containerPort, prefer a named `port` reference.

---

## Issue #4: Helm silently ignored unknown Cilium values

### Environment
- Cilium chart 1.20.2, Helm 4.2.4
- Date: 2026-10-23
- Context: Phase 3 — rendering Cilium before install

### Symptom
`helm template` succeeded, but the rendered ConfigMap had no setting for
`externalIPs.enabled` or `loadBalancer.IPAM.enabled`, even though both were in
`04-platform/cilium/values.yaml`. No warning was printed.

### Root cause
The Cilium 1.20 chart no longer exposes those keys. Helm merges arbitrary
values but only templates keys the chart knows about; unknown keys are accepted
and **discarded silently**. `helm template --debug` also does not fail.

### Investigation
```bash
helm show values cilium/cilium --version 1.20.2 | grep -i externalIP
# no externalIPs block (only disableExternalIPMitigation)
helm template ... | grep -i 'external-ips\|enable-lb-ipam'
# only enable-lb-ipam: "true" (chart default), no external-ips
grep -rn 'enable-external-ips' /tmp/cilium-chart/cilium/templates
# no matches -> key is gone, not a rename
```

### Resolution
Removed both dead blocks. LB IPAM is on by default in 1.20
(`enableLBIPAM: true`), and L2 announcements no longer need an externalIPs
toggle.

### Why this only works
The rendered ConfigMap is the only source of truth for the agent. A value that
does not appear there has no effect, regardless of what `values.yaml` says.
Keeping the dead keys would have created false confidence ("we enabled LB
IPAM") while the real behaviour depended on the chart default. Removing them
makes the file match the chart's actual API.

### Verification
```text
helm template ... -> exit 0, 37 resources
render contains: enable-lb-ipam: "true", enable-l2-announcements: "true"
render does NOT need externalIPs for Gateway VIP allocation
```

### Prevention
- After every values change: `helm template` and `grep` the rendered output for
  the setting you think you enabled.
- Pin the chart version and diff its `values.yaml` when upgrading.
- Prefer chart defaults over copying keys from older blog posts.

---

## Issue #5: Cilium on EKS — no PodCIDR and no VXLAN security-group rules

### Environment
- Cluster: AWS EKS 1.36.5
- CNI: Cilium 1.20.2 (VXLAN, kube-proxy replacement)
- Date: 2026-10-23
- Context: Phase 3 — first node join after installing Cilium

### Symptom
Cilium agents crash-looped with:
```text
level=warn msg="Waiting for k8s node information" error="required IPv4 PodCIDR not available"
```
After switching IPAM, pods on different nodes could not reach each other:
```text
$ kubectl exec nettest -- nslookup hubble-peer.kube-system.svc.cluster.local
;; connection timed out; no servers could be reached
$ kubectl exec nettest -- ping -c2 10.0.12.11
100% packet loss
```
`hubble-relay` was in `CrashLoopBackOff` with DNS timeouts to `172.20.0.10:53`.

### Root cause
Two independent gaps:
1. `ipam.mode: kubernetes` requires every node to have `spec.podCIDR`. EKS only
   allocates PodCIDRs when the VPC CNI (`aws-node`) runs, which this design
   intentionally removes. Without a PodCIDR, Cilium cannot allocate addresses.
2. The EKS node security group created by the module only allows ephemeral TCP
   and CoreDNS between nodes. Cilium VXLAN needs `UDP/8472`, and Cilium health
   checks need `TCP/4240`. Both were missing, so cross-node pod traffic was
   dropped while same-node traffic worked.

### Investigation
```bash
kubectl get node <node> -o jsonpath='{.spec.podCIDR}'   # empty
kubectl -n kube-system logs ds/cilium | grep PodCIDR     # required IPv4 PodCIDR not available
aws ec2 describe-security-group-rules --filters Name=group-id,Values=<node-sg>
# ingress: 1025-65535 tcp self, 53 tcp/udp self, cluster-SG all
# missing: 8472/udp self, 4240/tcp self
kubectl exec <pod-on-node-a> -- nc -zv <pod-on-node-b> 53   # timeout
```

### Resolution
1. `04-platform/cilium/values.yaml`: `ipam.mode: cluster-pool` with
   `clusterPoolIPv4PodCIDRList: [10.244.0.0/16]`, `clusterPoolIPv4MaskSize: 24`.
2. `01-terraform-eks/eks.tf`: added `node_security_group_additional_rules`
   for `UDP/8472` (VXLAN) and `TCP/4240` (health), both `self = true`.
3. Re-applied Cilium (`install-cni.sh`) and Terraform, then restarted
   `hubble-relay` so it could rebuild peer connections.

### Why this only works
The Cilium agent owns pod IP allocation and encapsulation. With EKS there is no
kube-controller-manager `--allocate-node-cidrs`, so the Kubernetes IPAM mode has
no PodCIDR to consume; `cluster-pool` makes the Cilium operator the allocator.
VXLAN then wraps every cross-node packet in UDP/8472 between node IPs, so the
node security group must explicitly allow that port between nodes. Same-node
traffic is never encapsulated, which is why DNS worked for some pods and failed
for others depending on scheduling.

### Verification
```text
kubectl -n kube-system get pods -l k8s-app=cilium   # 2/2 Running
kubectl exec nettest -- nslookup hubble-peer.kube-system.svc.cluster.local  # resolves
kubectl -n kube-system get pods -l k8s-app=hubble-relay   # 1/1 Running
```

### Prevention
- Keep the Cilium `cluster-pool` CIDR outside the VPC CIDR (`10.244.0.0/16`).
- Treat node SG rules as part of the CNI, not an afterthought; verify with a
  cross-node pod test during provisioning.
- Add a smoke check that resolves a Service name from two different nodes.

---

## Issue #6: EKS control plane cannot reach Cilium overlay pod IPs

### Environment
- Cluster: AWS EKS 1.36.5
- CNI: Cilium 1.20.2, `routingMode: tunnel` (VXLAN)
- Date: 2026-10-23
- Context: Phase 3 — installing ESO and metrics-server

### Symptom
ESO admission webhook and the metrics-server aggregated API failed:
```text
Internal error occurred: failed calling webhook
"validate.clustersecretstore.external-secrets.io": ...
Post "https://external-secrets-webhook.platform.svc:443/...": Address is not allowed

$ kubectl get apiservice v1beta1.metrics.k8s.io
... "Address is not allowed"
```
Inside the cluster, the same endpoints were reachable.

### Root cause
For service-backed webhooks and aggregated APIs, kube-apiserver resolves the
Service to its Endpoints and dials the **pod IP** directly. Cilium VXLAN pod
IPs (`10.244.0.0/16`) exist only on the nodes; the EKS control plane ENIs have
no route to that overlay. The control plane therefore rejects the destination
as "Address is not allowed". This is not a Cilium agent bug — overlay routing
by definition stops at the node.

### Investigation
```bash
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
# message: failing or missing response from https://10.244.1.35:10250 ... Address is not allowed
kubectl -n platform get endpoints external-secrets-webhook
# 10.244.0.141:10250  (pod IP, not node IP)
kubectl exec <pod> -- nc -zv 10.244.1.169 53   # works from a pod
```

### Resolution
For the lab, keep the overlay and move only the control-plane-facing servers
onto the node network:
- **ESO**: `webhook.create=false`, `certController.create=false`. The ESO
  controller syncs secrets without admission/validation or CRD conversion.
- **metrics-server**: `hostNetwork.enabled=true` and `containerPort=4443`.
  Endpoints become `<node-ip>:4443`, which is already allowed from the EKS
  cluster security group to nodes. Port 4443 avoids the kubelet's 10250.
- Left the Cilium overlay unchanged for workload traffic.

### Why this only works
The control plane can route to VPC addresses (node ENIs) but not to VXLAN
overlay addresses. `hostNetwork: true` gives the pod the node IP, so the
Endpoint is in the VPC CIDR and the existing `cluster-SG -> node:4443` rule
applies. Disabling the ESO webhook removes the only ESO component the control
plane had to call; secret reconciliation is controller-to-AWS, not
control-plane-to-pod. The production alternative is Cilium ENI IPAM with native
routing, where pod IPs are real VPC addresses.

### Verification
```text
kubectl get apiservice v1beta1.metrics.k8s.io   # Available=True
kubectl top nodes                              # returns CPU/memory
kubectl get clustersecretstore                 # READY=True
kubectl get externalsecret -A                  # SecretSynced=True
```

### Prevention
- Any future webhook or aggregated API on this cluster needs either
  `hostNetwork` or native/ENI routing.
- Prefer `hostNetwork` with an allowed non-conflicting port over weakening PSS.
- Document that PSS `baseline` forbids `hostNetwork`, so platform namespaces
  must choose: baseline + no webhooks, or privileged + webhooks.

---

## తెలుగు

- ప్రతి నిజమైన సమస్యకు ఇక్కడ ఒక ఎంట్రీ ఉంటుంది: లక్షణం → మూల కారణం → పరిశోధన → పరిష్కారం → **ఇది మాత్రమే ఎందుకు పనిచేస్తుంది** → ధృవీకరణ → నివారణ.
- "fix అయింది" అని మాత్రమే రాయకూడదు; ఎందుకు జరిగిందో వివరించాలి.
- **Why this only works** విభాగం తప్పనిసరి — ఆ ఫిక్స్ ఏ డిపెండెన్సీ వల్ల పనిచేస్తుందో చెప్పాలి.
- ఉదాహరణ (Issue #0): Cilium chaining mode లో Gateway API పనిచేయదు; kube-proxy replacement=true ఉన్నప్పుడే Cilium సర్వీస్ రూటింగ్ నియంత్రిస్తుంది, అప్పుడే Envoy కి VIP ప్రోగ్రామ్ అవుతుంది.
