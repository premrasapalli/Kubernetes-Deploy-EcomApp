# Issue #5 — EKS లో Cilium కి PodCIDR లేదు, VXLAN SG rules లేవు

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #5.

## 1. ఏం జరిగింది (Symptom)

Nodes join అయ్యాక Cilium agent crash-loop:

```text
level=warn msg="Waiting for k8s node information" error="required IPv4 PodCIDR not available"
```

IPAM మార్చాక కూడా వేరే node పై ఉన్న pods మాట్లాడుకోలేదు:

```text
$ kubectl exec nettest -- nslookup hubble-peer.kube-system.svc.cluster.local
;; connection timed out; no servers could be reached

$ kubectl exec nettest -- ping -c2 10.0.12.11
100% packet loss
```

`hubble-relay` కూడా `CrashLoopBackOff` లో ఉంది (DNS timeout).

## 2. అసలు కారణం (Root cause)

రెండు వేర్వేరు సమస్యలు:

1. `ipam.mode: kubernetes` కి ప్రతి node కి `spec.podCIDR` కావాలి. EKS లో
   `aws-node` (VPC CNI) నడిస్తేనే podCIDR ఇస్తుంది. మనం Cilium native CNI
   వాడుతున్నాం కాబట్టి podCIDR ఖాళీగా ఉంది.
2. EKS node security group లో node-to-node ephemeral TCP, CoreDNS మాత్రమే
   ఉన్నాయి. Cilium VXLAN కి `UDP/8472`, health checks కి `TCP/4240` లేవు.
   అందుకే same-node pods పనిచేశాయి, cross-node pods పనిచేయలేదు.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
kubectl get node <node> -o jsonpath='{.spec.podCIDR}'   # ఖాళీ
kubectl -n kube-system logs ds/cilium | grep PodCIDR     # required IPv4 PodCIDR not available
aws ec2 describe-security-group-rules --filters Name=group-id,Values=<node-sg>
# 1025-65535 tcp self, 53 tcp/udp self, cluster-SG all మాత్రమే
# 8472/udp self, 4240/tcp self లేవు
kubectl exec <pod-a> -- nc -zv <pod-b> 53               # timeout
```

## 4. పరిష్కారం (Resolution)

1. `04-platform/cilium/values.yaml`:
   ```yaml
   ipam:
     mode: cluster-pool
     operator:
       clusterPoolIPv4PodCIDRList:
         - 10.244.0.0/16
       clusterPoolIPv4MaskSize: 24
   ```
2. `01-terraform-eks/eks.tf` లో `node_security_group_additional_rules`:
   - `UDP/8472` — VXLAN (self)
   - `TCP/4240` — Cilium health (self)
3. `install-cni.sh` తో Cilium upgrade, Terraform apply, `hubble-relay` restart.

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

EKS లో kube-controller-manager `--allocate-node-cidrs` నడవదు. అందుకే
`kubernetes` IPAM కి ఇవ్వడానికి PodCIDR లేదు. `cluster-pool` లో Cilium operator
నే allocator అవుతుంది. VXLAN లో ప్రతి cross-node packet `UDP/8472` లో
node-to-node వెళ్తుంది; SG లో ఆ port allow చేయకపోతే packet drop. Same-node
traffic కి VXLAN అవసరం లేదు — అందుకే కొన్ని pods పనిచేసినట్టు అనిపించింది.

## 6. ధృవీకరణ (Verification)

```text
kubectl -n kube-system get pods -l k8s-app=cilium        # 2/2 Running
kubectl exec nettest -- nslookup hubble-peer...          # resolve అవుతుంది
kubectl -n kube-system get pods -l k8s-app=hubble-relay  # 1/1 Running
```

## 7. మళ్లీ రాకుండా (Prevention)

- `cluster-pool` CIDR VPC CIDR (`10.0.0.0/16`) తో overlap కాకూడదు.
- CNI SG rules ను provisioning లో భాగంగా చూడండి; రెండు వేరే nodes పై ఉన్న
  pods తో DNS/cross-node test చేయండి.
- Smoke check: రెండు nodes నుంచి ఒక Service name resolve అవుతుందా చూడండి.
