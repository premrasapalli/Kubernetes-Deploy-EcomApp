# Phase 3 — Platform (Cilium, Gateway API, LB IPAM, ESO, metrics-server)

> ఇంగ్లీష్: `docs/ARCHITECTURE.md` Section 11, `docs/ISSUES.md` Issues #0, #4, #5, #6.

## `04-platform/cilium/values.yaml`

### ముఖ్యమైన సెట్టింగ్‌లు
- `kubeProxyReplacement: true` — Cilium నే Service routing చేస్తుంది. Gateway API కి ఇది తప్పనిసరి.
- `ipam.mode: cluster-pool` — pod IP లను Cilium operator `10.244.0.0/16` నుంచి ఇస్తుంది.
  - **ఎందుకు:** EKS లో VPC CNI లేకపోతే nodes కి `spec.podCIDR` ఉండదు; అందుకే
    `kubernetes` IPAM పనిచేయదు (Issue #5).
- `routingMode: tunnel` — VXLAN; native routing కి ENI/సబ్‌నెట్ షరతులు అవసరం లేదు.
  - **SG rule:** node-to-node `UDP/8472` (VXLAN) + `TCP/4240` (health) తప్పనిసరి;
    `01-terraform-eks/eks.tf` లో `node_security_group_additional_rules` ఉంది (Issue #5).
- `k8sServiceHost/Port` — install సమయంలో EKS endpoint (script `--set` చేస్తుంది). లేకపోతే
  kube-proxy లేనందున Cilium API server ను కనుక్కోలేదు.
- `gatewayAPI.enabled: true` — GatewayClass `cilium` ను Cilium నిర్వహిస్తుంది.
- `l2announcements.enabled: true` — VIP ను node NIC MAC తో LAN కి ప్రకటిస్తుంది.
- LB IPAM 1.20 లో డిఫాల్ట్ (`enableLBIPAM: true`); `externalIPs` key ఇక లేదు (Issue #4).
- `operator.replicas: 1` — lab ఖర్చు/వనరుల ఆదా.
- `hubble`: relay + UI — flow observability.
- `bpf.datapathMode=netkit`? ఇక్కడ `netkit` వాడలేదు; default veth.
- `rolloutCiliumPods: true`, `updateStrategy` — upgrades సురక్షితం.

### ఎందుకు chaining కాదు
Issue #0 చూడండి: chaining లో Gateway API పనిచేయదు; Envoy VIP కి Cilium eBPF service path కావాలి.

## `04-platform/gateway-api/*`

### `gatewayclass.yaml`
- `GatewayClass` name `cilium`, `controllerName: io.cilium/gateway-controller`.
- **ఎందుకు:** cluster-scoped; ఏ controller Gateway లను నిర్వహిస్తుందో చెబుతుంది.

### `gateway.yaml`
- `Gateway retailx-gateway` namespace `retailx`.
- `gatewayClassName: cilium`, listener HTTP:80.
- annotation `io.cilium/lb-ipam-ips: 10.0.11.250` — VIP ను ఇక్కడే కోరుతున్నాం.
- `allowedRoutes.namespaces.from: Same` — వేరే namespace route attach కాకూడదు (భద్రత).

### `httproute.yaml`
- hostname `retailx.example.com`.
- `/api/products` → product-api:8081, `/api/cart` → cart-api:8082,
  `/api/orders` → order-api:8083, `/` → frontend:80.
- **ముఖ్యం:** `backendRefs.port` = **Service port**, containerPort కాదు (Issue #3).

### `lb-ipam.yaml`
- `CiliumLoadBalancerIPPool retailx-pool` — `10.0.11.250/32`.
- `CiliumL2AnnouncementPolicy` — `interfaces: ["^eth[0-9]+"]`, `externalIPs: true`, `loadBalancerIPs: true`.
- **ఎందుకు:** AWS LB ఖర్చు లేకుండా స్థిరమైన VIP; LAN లో ARP ద్వారా reachable.

## `04-platform/external-secrets/clustersecretstore.yaml`
- `ClusterSecretStore aws-secretsmanager`, provider `aws` → Secrets Manager, region `us-east-1`.
- auth: `jwt.serviceAccountRef` → `platform/external-secrets` (IRSA).
- **ఎందుకు:** ESO ఆ SA గా AWS కి వెళ్తుంది; రహస్యాలు Git లో ఉండవు.

## `04-platform/scripts/install-cni.sh`
1. Gateway API `v1.5.1` experimental CRDs (server-side apply).
2. EKS endpoint నుంచి host తీసి `k8sServiceHost` సెట్.
3. `helm upgrade --install cilium 1.20.2 -f values.yaml`.
- `--wait` లేదు — nodes ఇంకా లేవు; pods తర్వాత start అవుతాయి.

## `04-platform/scripts/install-addons.sh`
1. metrics-server (`hostNetwork.enabled=true`, `containerPort=4443`) → HPA.
   - **ఎందుకు hostNetwork:** EKS control plane Cilium overlay pod IP కి reach కాదు
     (Issue #6). Node SG లో 4443 already allowed; kubelet 10250 conflict bypass.
2. `platform` namespace + ESO SA (IRSA annotation `terraform output eso_role_arn`).
3. ESO Helm, `installCRDs=true`, `serviceAccount.create=false` (మన SA వాడాలి).
   - `webhook.create=false`, `certController.create=false` — control plane pod IP కి
     reach కాదు, PSS baseline hostNetwork reject చేస్తుంది (Issue #6).
   - ESO controller webhook లేకుండానే AWS Secrets Manager నుంచి sync చేస్తుంది.
4. CRD Established కోసం wait → ClusterSecretStore apply.
5. LB IPAM pool (`cilium.io/v2`) + L2 announcement policy apply.
6. Optional `INSTALL_MONITORING=true` → kube-prometheus-stack (ఇంకా install చేయలేదు).

## ధృవీకరణ
```bash
kubectl get nodes                                  # 2 Ready
kubectl get gatewayclass                           # ACCEPTED=True
kubectl -n retailx get gateway,httproute           # PROGRAMMED / Accepted
kubectl -n kube-system get pods -l k8s-app=cilium  # 2/2 Running
kubectl -n kube-system get pods -l k8s-app=hubble-relay # 1/1 Running
kubectl -n platform get pods                       # external-secrets Running
kubectl get clustersecretstore                     # READY=True
kubectl get externalsecret -A                      # SecretSynced=True
kubectl get apiservice v1beta1.metrics.k8s.io      # Available=True
kubectl top nodes                                  # metrics API OK
kubectl get ciliumloadbalancerippool               # 10.0.11.250 gateway కి used
```

Cross-node DNS check (Issue #5 regression guard):
```bash
kubectl exec <pod-on-node-a> -- nslookup kubernetes.default.svc.cluster.local
```
