# Issue #6 — EKS control plane కి Cilium overlay pod IPs reach కావు

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #6.

## 1. ఏం జరిగింది (Symptom)

ESO webhook, metrics-server aggregated API రెండూ fail అయ్యాయి:

```text
Internal error occurred: failed calling webhook
"validate.clustersecretstore.external-secrets.io": ...
Post "https://external-secrets-webhook.platform.svc:443/...": Address is not allowed

$ kubectl get apiservice v1beta1.metrics.k8s.io
... "Address is not allowed"
```

కానీ cluster లోపలి pods నుంచి అదే endpoints reach అయ్యాయి.

## 2. అసలు కారణం (Root cause)

Service-backed webhooks మరియు aggregated APIs కోసం kube-apiserver Service ను
Endpoints గా resolve చేసి **pod IP** కి నేరుగా dial చేస్తుంది. Cilium VXLAN
pod IPs (`10.244.0.0/16`) nodes పైనే ఉంటాయి; EKS control plane ENI కి ఆ
overlay కి route లేదు. అందుకే "Address is not allowed". ఇది Cilium bug కాదు —
overlay routing node దగ్గరే ఆగిపోతుంది.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
# message: ... https://10.244.1.35:10250 ... Address is not allowed
kubectl -n platform get endpoints external-secrets-webhook
# 10.244.0.141:10250   (pod IP, node IP కాదు)
kubectl exec <pod> -- nc -zv 10.244.1.169 53   # cluster లోపల పనిచేస్తుంది
```

## 4. పరిష్కారం (Resolution)

Lab లో overlay ను అలాగే ఉంచి, control plane మాట్లాడే servers ను మాత్రమే
node network కి మార్చాం:

- **ESO**: `webhook.create=false`, `certController.create=false`.
  ESO controller webhook లేకుండానే secrets sync చేస్తుంది.
- **metrics-server**: `hostNetwork.enabled=true`, `containerPort=4443`.
  Endpoint `<node-ip>:4443` అవుతుంది; EKS cluster SG నుంచి node కి 4443
  already allowed. Kubelet 10250 తో conflict రాకుండా 4443 వాడాం.
- Workload traffic కోసం Cilium overlay మార్చలేదు.

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

Control plane కి VPC addresses (node ENIs) route ఉంటాయి, VXLAN overlay కి
ఉండదు. `hostNetwork: true` pod కి node IP ఇస్తుంది, కాబట్టి Endpoint VPC CIDR
లో ఉంటుంది మరియు ఇప్పటికే ఉన్న `cluster-SG -> node:4443` rule వర్తిస్తుంది.
ESO webhook disable చేయడం వల్ల control plane నుంచి pod కి call మిగలదు;
secret reconciliation controller నుంచి AWS కి మాత్రమే. Production లో
పరిష్కారం Cilium ENI IPAM + native routing — అప్పుడు pod IPs నిజమైన VPC
addresses అవుతాయి.

## 6. ధృవీకరణ (Verification)

```text
kubectl get apiservice v1beta1.metrics.k8s.io   # Available=True
kubectl top nodes                               # CPU/memory వస్తుంది
kubectl get clustersecretstore                  # READY=True
kubectl get externalsecret -A                   # SecretSynced=True
```

## 7. మళ్లీ రాకుండా (Prevention)

- భవిష్యత్ webhook / aggregated API కి `hostNetwork` లేదా native/ENI routing
  తప్పనిసరి.
- PSS `baseline` లో `hostNetwork` నిషేధం; platform namespace కి "baseline +
  webhooks లేవు" లేదా "privileged + webhooks" అనే ఎంపిక ఉంటుంది.
- PSS ను బలహీనపరచడం కంటే allowed non-conflicting port తో `hostNetwork`
  వాడడం మేలు.
