# Learnings

Personal notes per phase. Keep it short: what surprised you, what you got wrong,
what you would do differently. This is your interview prep sheet.

## Phase 0 — Workspace & docs

- Why docs-first: failures are unavoidable; a structured issue log turns pain into
  reusable knowledge.
- Why separate `docs/te/`: explanations in Telugu stay next to the English truth
  without polluting production manifests.
- Cost is an architecture constraint, not an afterthought. Designing for
  "destroy after each session" changes choices (single spot node, LB IPAM, no NAT).

**Open questions:**
- How much of the prod topology can we keep while staying under ~$10/session?

## Phase 1 — App source

- Health must mean "can serve traffic", not "process is alive". Product API returns
  `503` until its schema is ready — that is what a readiness probe should see.
- Start-order races are normal, not bugs. Bounded retry loops (30 × 3s) plus probes
  make pods survive Postgres/Redis coming up late without CrashLoopBackOff noise.
- Images should be built for the target architecture (`linux/amd64` on Apple Silicon),
  otherwise EKS nodes pull an arm64 image and fail with `exec format error`.
- Unprivileged nginx (UID 101, port 8080) is not a preference — root port 80 is
  rejected by PSS `restricted` and by `runAsNonRoot`.
- Local correctness needs a proxy: the browser can only call same-origin `/api/*`.
  Locally `nginx.local.conf` does that; in the cluster Gateway API does it. The app
  code should never hardcode service hostnames.
- Multi-stage builds keep dev dependencies out of runtime images and make
  `npm ci --omit=dev` the only install path (lockfile is the source of truth).

**Open questions:**
- Should order creation decrement stock atomically? Currently both APIs write
  independently; Phase 6 could add a Postgres transaction across tables.
- How much auth is enough for a demo? `userId=demo` is a placeholder, not security.

## Phase 2 — Terraform EKS
_TODO_

## Phase 3 — Platform (Cilium, Gateway API, ESO)

- CNI choice is also a security-group and control-plane decision. Cilium VXLAN
  needs UDP/8472 + TCP/4240 between nodes (Issue #5), and EKS control plane
  cannot dial overlay pod IPs (Issue #6). Neither shows up until the first
  webhook or aggregated API.
- EKS does not allocate PodCIDRs without the VPC CNI, so `ipam.mode: kubernetes`
  cannot work; `cluster-pool` makes the Cilium operator the allocator.
- Platform components that the API server must call (webhooks, metrics-server)
  need node-routable endpoints: `hostNetwork` with an allowed port, or native
  routing. PSS `baseline` rejects `hostNetwork`, so namespace policy and
  component choice must be decided together.
- `helm --wait` is not enough for ESO: the webhook can take longer than the CRD
  to become ready. Wait for the webhook Deployment/Endpoints before applying a
  ClusterSecretStore.
- The EKS module ignores `scaling_config.desired_size` after node group
  creation; scaling must be an explicit `aws eks update-nodegroup-config`.

**Open questions:**
- Is ENI IPAM + native routing worth the IAM and subnet complexity over
  `hostNetwork` for control-plane-facing services?

## Phase 4 — Manifests (RBAC, PSS, policies)
_TODO_

## Phase 5 — End-to-end validation
_TODO_

## Phase 6 — Break/fix
_TODO_

## Phase 7 — Teardown rehearsal
_TODO_

---

## తెలుగు

- ప్రతి ఫేజ్ తర్వాత: ఏం నేర్చుకున్నాం, ఏది ఆశ్చర్యం కలిగించింది, తర్వాత ఏం మార్చాలి — ఇక్కడ రాయండి.
- ఇది మీ ఇంటర్వ్యూ నోట్స్‌గా పనిచేస్తుంది.
- "ఖర్చు కూడా ఆర్కిటెక్చర్ నిర్ణయమే" — destroy-after-session అనే నియమం వల్ల సింగిల్ spot node, LB IPAM, NAT లేకుండా డిజైన్ చేశాం.
