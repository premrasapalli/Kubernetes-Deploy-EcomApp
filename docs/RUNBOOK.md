# Runbook

Copy/paste debugging playbook. Keep commands safe to run repeatedly.

## 0. Context

```bash
aws sts get-caller-identity
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -v Running
```

## 1. Is the cluster healthy?

```bash
kubectl get nodes                          # all Ready?
kubectl -n kube-system get ds              # cilium present, no aws-node/kube-proxy
kubectl -n kube-system get pods            # cilium, cilium-envoy, coredns, operator
kubectl -n kube-system logs deploy/cilium-operator --tail=50
kubectl -n kube-system logs ds/cilium --tail=50
```

## 2. Is the Gateway working?

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
kubectl describe gateway retailx-gateway -n retailx    # events at the bottom
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.kube-proxy-replacement}'
kubectl get ciliumloadbalancerippool -o wide
kubectl get ciliuml2announcementpolicy -o yaml
```

Expected: `ACCEPTED=True`, `PROGRAMMED=True`, `ADDRESS` set, pool not exhausted.

## 3. Is DNS working?

```bash
kubectl run dnstest --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup product-api.retailx.svc.cluster.local
```

## 4. Is the pod reachable? (identity first, then path)

```bash
# direct pod/service (bypasses Gateway)
kubectl exec -n retailx deploy/frontend -- wget -qO- http://product-api:8081/health

# through the Gateway VIP
kubectl exec -n retailx deploy/frontend -- wget -qO- http://<GATEWAY_IP>/health
```

## 5. Why am I getting 403 / dropped?

```bash
hubble observe --namespace retailx --verdict DROPPED --last 50
hubble observe --namespace retailx --protocol http --last 50
hubble observe --namespace retailx --to-pod retailx/<pod> --last 50
cilium-dbg status --verbose   # inside a cilium pod
kubectl get ciliumnetworkpolicy -n retailx -o yaml
```

Remember: Gateway L7 policy is enforced on **both hops**:
- client -> Gateway VIP (client egress policy)
- Gateway -> backend (backend ingress from `reserved:ingress`)

## 6. Pod won't start

```bash
kubectl -n retailx describe pod <pod>
kubectl -n retailx get events --sort-by=.lastTimestamp | tail -30
kubectl -n retailx logs <pod> --previous
kubectl get psa -n retailx 2>/dev/null || kubectl get ns retailx -o yaml | grep pod-security
kubectl auth can-i --list --as=system:serviceaccount:retailx:<sa>
```

Common causes: image pull (ECR/IRSA), restricted PSS (securityContext), missing secret,
resource quota, wrong node selector / topology spread.

## 7. AWS access from a pod (IRSA)

```bash
kubectl -n retailx exec deploy/<svc> -- env | grep AWS
kubectl -n retailx get sa <sa> -o yaml | grep eks.amazonaws.com/role-arn
aws iam get-role --role-name <role> --query 'Role.AssumeRolePolicyDocument'
aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer'
```

## 8. Force a clean re-apply

```bash
kubectl kustomize 03-k8s-manifests/overlays/dev | kubectl apply -f -
kubectl rollout restart deploy -n retailx
kubectl rollout status deploy -n retailx --timeout=120s
```

## 9. Teardown

```bash
bash 05-scripts/teardown.sh
```

---

## తెలుగు

- ఏదైనా సమస్య వచ్చినప్పుడు ఈ క్రమంలో వెతకండి: క్లస్టర్ → గేట్‌వే → DNS → పాడ్ → పాలసీ.
- `kubectl get nodes` లో `Ready` లేకపోతే ముందు Cilium పరిశీలించండి — Cilium లేకపోతే pod network ఉండదు.
- 403 వస్తే `hubble observe --verdict DROPPED` చూడండి; సాధారణంగా రెండు హాప్‌లలో ఒక పాలసీ మిస్ అయి ఉంటుంది.
- పాడ్ రాకపోతే `describe` + `events` + `logs --previous` — ఈ మూడూ చాలు.
- IRSA పనిచేయకపోతే ServiceAccount annotation మరియు OIDC issuer రెండూ సరిపోల్చండి.
- పని అయ్యాక `teardown.sh` తప్పక నడపండి.
