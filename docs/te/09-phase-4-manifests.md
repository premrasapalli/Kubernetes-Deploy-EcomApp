# Phase 4 — Kubernetes manifests (base + dev overlay)

> రూట్: `03-k8s-manifests/`. render: `kubectl kustomize 03-k8s-manifests/overlays/dev`.

## `base/namespaces.yaml`
- `retailx`: `pod-security.kubernetes.io/enforce: restricted` (app).
- `platform`: `baseline` (ESO/monitoring కి కొంచెం సడలింపు).
- **ఎందుకు:** PSS restricted అంటే non-root, no privilege escalation, seccomp, dropped caps.
  ఇది డిఫాల్ట్; ఉల్లంఘించే pod సృష్టించబడదు.

## `base/serviceaccounts/*.yaml`
- `frontend`, `product-api`, `cart-api`, `order-api`, `postgres`, `redis`, `nettest`.
- app SAs కి `automountServiceAccountToken: false`.
- **ఎందుకు:** app కి K8s API అవసరం లేదు; token mount చేయకపోతే దొంగిలించడానికి ఏమీ ఉండదు.
  `nettest` కి మాత్రమే debug RBAC ఉంది.

## `base/debug-rbac.yaml`
- Role `debug-reader` (pods/services/endpoints get/list), RoleBinding → `nettest`.
- **ఎందుకు:** ట్రబుల్‌షూట్ చేసే pod కి చదివే అనుమతి మాత్రమే; రాయడం/delete లేదు.

## `base/storageclass/gp3.yaml`
- `ebs.csi.aws.com`, `WaitForFirstConsumer`, `allowVolumeExpansion: true`, default.
- **ఎందుకు:** EBS volume అదే AZ లో పడాలి; pod schedule అయ్యాకే volume సృష్టి.

## `base/configmaps/app-config.yaml`
- `NODE_ENV`, `REDIS_URL`, `DB_HOST/PORT/NAME`, `PRODUCT_API_URL` మొదలైనవి.
- **ఎందుకు:** non-secret config మాత్రమే; passwords Secrets Manager నుంచి ESO ద్వారా.

## `base/secrets-external/externalsecrets.yaml`
- `ExternalSecret postgres-credentials` → `retailx/postgres`, `jwt-secret` → `retailx/jwt`.
- `refreshInterval` తో sync; target K8s Secret పేర్లు.
- **ఎందుకు:** Git లో secret లేదు; AWS నుంచి ఆటోమేటిక్‌గా K8s కి.

## `base/services/services.yaml`
- frontend `80 → 8080`, product `8081`, cart `8082`, order `8083`, postgres `5432`, redis `6379`.
- ClusterIP మాత్రమే (Gateway VIP ద్వారా బయటకు).
- **గుర్తుంచుకోండి:** HTTPRoute backendRef ఈ **Service ports** నే వాడాలి (Issue #3).

## `base/workloads/*.yaml`
- `frontend` (3 replicas, nginx-unprivileged 8080), `product-api`/`cart-api`/`order-api` (2 each),
  `postgres`/`redis` StatefulSet (1 each, PVC), `nettest` (curl, /tmp emptyDir).
- అందరికీ: `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`.
- probes: startup (30×2s), readiness, liveness; resources requests/limits.
- **ఎందుకు:** PSS restricted కి అవసరం + rolling updates లో traffic సురక్షితం.
- PostgreSQL: `PGDATA=/var/lib/postgresql/data/pgdata` — volume root లో ఉన్న `lost+found` సమస్య నివారణ.

## `base/pdb/pdb.yaml`
- frontend `minAvailable: 1`, APIs `minAvailable: 1`.
- **ఎందుకు:** voluntary disruption (node drain) లో అన్నీ ఒకేసారి పోకూడదు.

## `base/hpa/hpa.yaml`
- frontend 3–6 (CPU 70%), APIs 2–4 (CPU 75%).
- **ఎందుకు:** metrics-server ఉంది; lab లో ఎక్కువ కాపీలు సృష్టించదు కానీ pattern చూపుతుంది.

## `base/networkpolicies/*.yaml`
- `default-deny`: `endpointSelector: {}` ingress+egress deny; `allow-dns` మాత్రం kube-dns :53.
- `frontend-l7`: ingress `fromEntities: ingress` (Cilium Gateway) 8080, L7 GET `/`, `/index.html`,
  `/app.js`, `/styles.css`; health probes; nettest. Egress అవసరం లేదు.
- `product-api`/`cart-api`/`order-api`:
  - ingress: Gateway (`fromEntities: ingress`) + nettest, L7 method/path allow-list; health.
  - egress: postgres/redis **అదే namespace** endpoint labels, DB/Redis port; DNS.
- `data.yaml`: postgres ← product+order 5432; redis ← cart 6379; health.
- `nettest.yaml`: nettest egress 80/8080–8083, 5432/6379 only.
- **ఎందుకు L7:** method/path allow-list లేకపోతే Gateway ద్వారా ఏ path అయినా వెళ్తుంది.
  `/admin` వంటివి Envoy స్థాయిలోనే 403.
- **రెండు హాప్‌లు:** client→Gateway (`ingress` entity), Gateway→backend (policy) రెండూ allow కావాలి.

## `base/kustomization.yaml`
- అన్ని resources జాబితా; common labels.
- **ఎందుకు:** ఒకే `kubectl apply -k` తో deterministic order.

## `overlays/dev/kustomization.yaml`
- base ను reference; dev కి మాత్రం మార్పులు (replicas/tag ఇక్కడ కావచ్చు).
- image placeholders `IMAGE_PREFIX/retailx/<svc>:IMAGE_TAG` — deploy స్క్రిప్ట్ sed చేస్తుంది.
- **ఎందుకు:** prod overlay తర్వాతి ఫేజ్ లో అదే base నుంచి.

## ధృవీకరణ
```bash
kubectl kustomize 03-k8s-manifests/overlays/dev >/tmp/render.yaml
grep -c '^kind:' /tmp/render.yaml     # 45
```
