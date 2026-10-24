# [TELUGU EXPLANATION]
# PURPOSE      : Day-to-day debugging & operations కోసం Runbook
# WHAT IT DOES : త్వరగా use చేయగల kubectl/cilium/hubble/helm/aws cmds + Telugu explanation
# WHY ENTERPRISE: On-call/triage సమయంలో time save అవుతుంది
# HOW TO USE   : Issue వచ్చినప్పుడు ఈ నుండి start చేయి
# NOTES        : కొత్త debug cmds కనుక్కున్నప్పుడు ఇక్కడ add చేయి

# RUNBOOK.md - Debugging & Operations Runbook (Telugu)

> Target: AWS EKS + Cilium (Native) + Gateway API + retailx app

## 1) Cluster Health Check
```bash
# Cluster info చూడటం
kubectl cluster-info

# Nodes status
kubectl get nodes -o wide

# System pods
kubectl get pods -n kube-system
```
**తెలుగు:** Nodes Ready గా ఉన్నాయా? Cilium pods running గా ఉన్నాయా? check చేయడం మొదటి పని.

## 2) Cilium Specific
```bash
# Cilium status
cilium status --wait

# Cilium config
kubectl -n kube-system get cm cilium-config -o yaml | grep -A 5 -B 5 kube-proxy

# Endpoints
kubectl get ciliumendpoints -A | head -20

# Identity
kubectl get ciliumidentities | head -10
```
**తెలుగు:** CNI dataplane correct గా ఉందో లేదో చూడటానికి.

## 3) Gateway API
```bash
# GatewayClass
kubectl get gatewayclass

# Gateway
kubectl get gateway -A

# HTTPRoute
kubectl get httproute -A

# Gateway details
kubectl describe gateway ecommerce-gateway -n retailx 2>/dev/null || kubectl describe gateway -A
```
**తెలుగు:** Gateway programmed/accepted అయిందా check చేయాలి.

## 4) retailx App Debug
```bash
# All in retailx
kubectl get all -n retailx

# Pods detail
kubectl get pods -n retailx -o wide

# Describe pod
kubectl describe pod <POD_NAME> -n retailx

# Logs (current + previous)
kubectl logs <POD_NAME> -n retailx
kubectl logs <POD_NAME> -n retailx --previous

# Events
kubectl get events -n retailx --sort-by=.metadata.creationTimestamp | tail -30
```

## 5) NetworkPolicy / CiliumNetworkPolicy
```bash
# K8s NetworkPolicy
kubectl get networkpolicy -A

# CiliumNetworkPolicy
kubectl get ciliumnetworkpolicy -A
kubectl get ciliumclusterwidenetworkpolicy -A

# Hubble observe (flows)
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &
hubble observe --server localhost:4245 -n retailx --last 30
```
**తెలుగు:** Traffic allow/dropped అయిందో చూడడానికి Hubble బెస్ట్ tool.

## 6) DNS / Connectivity Tests
```bash
# Test DNS
kubectl run tmp-dns --rm -it --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default

# Curl from debug pod
kubectl run nettest --rm -it --restart=Never --image=curlimages/curl -n retailx -- curl -v http://product-api:8080/health
```

## 7) IRSA / External Secrets
```bash
# ServiceAccounts
kubectl get sa -n retailx

# ExternalSecrets
kubectl get externalsecret -A
kubectl get secretstore -A
kubectl get clustersecretstore -A

# Check secret synced
kubectl get secret -n retailx
```

## 8) AWS Free-Tier Quick Checks
```bash
# EKS nodes
aws eks describe-nodegroup --cluster-name <CLUSTER_NAME> --nodegroup-name <NG_NAME> --region us-east-1 2>/dev/null

# EC2 (nodes count)
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=<CLUSTER_NAME>" --region us-east-1 --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]'
```

## 9) Quick Triage Flow (Telugu)
1. **Symptom** - ఏమి జరగలేదో చూడు (curl/connection refused/503/403)
2. **Pods** - `kubectl get pods` - Running/CrashLoopBackOff/Pending
3. **Events** - `kubtag get events --sort-by=..`
4. **Logs** - App logs చూడు
5. **Network** - Hubble + NP/CNP check
6. **Gateway** - GatewayClass/Gateway/HTTPRoute
7. **Fix & Document** - Fix చేసి `ISSUES.md` లో log చేయి

**Note:** కొత్త issue వచ్చినప్పుడల్లా ఈ Runbook కి add చేస్తూనే ఉండు.
