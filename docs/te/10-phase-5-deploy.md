# Phase 5 — Provision, build, deploy, validate, teardown

> అన్ని స్క్రిప్ట్‌లు `05-scripts/`, platform స్క్రిప్ట్‌లు `04-platform/scripts/`.

## క్రమం (ఎప్పుడూ ఇదే)
```bash
bash 05-scripts/00-preflight.sh
bash 05-scripts/01-provision.sh        # ~15–20 నిమిషాలు
bash 05-scripts/02-build-push.sh
bash 05-scripts/03-deploy-app.sh
bash 05-scripts/04-validate.sh
bash 05-scripts/99-teardown.sh         # సెషన్ చివర్లో తప్పనిసరి
```

## `00-preflight.sh`
- `aws/terraform/kubectl/helm/docker` ఉన్నాయా, Docker daemon నడుస్తోందా.
- `aws sts get-caller-identity` — సరైన account (515966533768) అని నిర్ధారణ.
- EKS ఖర్చు హెచ్చరిక చూపిస్తుంది (~$73/నెల).
- **ఎందుకు:** తప్పు account లో cluster సృష్టించడం, Docker లేకుండా build చేయడం నివారణ.

## `01-provision.sh` (two-stage)
1. `terraform init` + `apply -var node_desired_size=0` → VPC/EKS/ECR/IRSA/Secrets.
2. `aws eks update-kubeconfig`.
3. `install-cni.sh` → Gateway API CRDs + Cilium (nodes లేకుండా).
4. `apply -var node_desired_size=2` → node group join; Cilium CNI ఇప్పటికే ఉంది.
5. `kubectl wait nodes Ready` → Cilium/CoreDNS rollout → `install-addons.sh`.
- **ఎందుకు ఈ క్రమం:** nodes కి CNI లేకపోతే NotReady; `aws-node` లేదు (Cilium native).
  Cilium `ipam.mode=kubernetes` కాబట్టి operator లేకుండా agent మొదటి node ను Ready చేస్తుంది.

## `02-build-push.sh`
- `REGISTRY=$(terraform output -raw ecr_registry)`.
- `aws ecr get-login-password | docker login`.
- ప్రతి సర్వీస్: `docker build --platform linux/amd64 -t $REGISTRY/retailx/<svc>:$TAG`.
- `docker push`.
- **ఎందుకు `linux/amd64`:** మీ Mac arm64 అయినా EKS nodes x86; లేకపోతే `exec format error`.
- **ఎందుకు `TAG`:** ECR IMMUTABLE; ప్రొడక్షన్ లో git SHA వాడాలి.

## `03-deploy-app.sh`
1. `kubectl kustomize overlays/dev | sed IMAGE_PREFIX/IMAGE_TAG | kubectl apply -f -` —
   namespaces, SAs, config, secrets, workloads, policies.
2. GatewayClass → LB IPAM → Gateway → HTTPRoute.
3. ESO ExternalSecrets Ready కోసం wait (DB secret అందకపోతే pod `CreateContainerConfigError`).
4. rollouts: frontend, APIs, postgres, redis, nettest.
- **ఎందుకు ఈ order:** namespace మొదట; Gateway ఉన్నప్పుడే Route attach అవుతుంది;
  secrets ముందు ఉంటే DB pod మొదటి ప్రయత్నంలోనే start అవుతుంది.

## `04-validate.sh`
- GatewayClass/Gateway/HTTPRoute status.
- Gateway ద్వారా: `/` → 200 (`server: envoy`), `/admin` → 403 (L7 deny),
  `/api/products` → 200, cart/order POST → 201.
- Direct service DNS (`frontend.retailx.svc`) → 200 nginx (Gateway bypass).
- ExternalSecrets, K8s Secrets, HPA, PDB ఉన్నాయా.
- **ఎందుకు nettest:** node/ pod నుంచి VIP కి curl చేయడానికి; మీ laptop నుంచి VIP reachable కాదు
  (private subnet + L2). బయటి నుంచి test చేయాలంటే SSM port-forward వాడండి.
- `/admin` 403 రావడం **విజయం** — policy పనిచేస్తున్నట్టు రుజువు.

## `99-teardown.sh`
1. HTTPRoute → Gateway → `kubectl delete -k overlays/dev`.
2. PVC/LB cleanup కోసం వేచి ఉండడం.
3. `terraform destroy` (ECR force_delete, Secrets recovery 0).
4. `aws eks list-clusters` ఖాళీగా ఉందా చూడడం.
- **ఎందుకు:** EKS/NAT ప్రతి గంటకు డబ్బు; destroy లేకపోతే నెలకు ~$125.

## సాధారణ సమస్యలు (ఇక్కడ డాక్యుమెంట్ చేస్తాం)
- Issue #0: Cilium chaining → Gateway API పనిచేయదు.
- Issue #1: EKS module inputs rename.
- Issue #2: `kustomize` బైనరీ లేదు → `kubectl kustomize`.
- Issue #3: HTTPRoute containerPort vs Service port.
- తదుపరి నిజమైన ఫెయిల్యూర్లు `docs/ISSUES.md` + `docs/te/issues/` లో చేరతాయి.
