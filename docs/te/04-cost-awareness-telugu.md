# [TELUGU EXPLANATION]
# PURPOSE      : AWS Free Tier ని mindful గా ఉంచడానికి Cost Awareness doc
# WHAT IT DOES : Create అయ్యే resources, approx cost, save tips, teardown reminders
# WHY ENTERPRISE: Cost Awareness కూడా enterprise mindset లో భాగం
# HOW TO USE   : ప్రతీ phase ముందు/తర్వాత check చేయడం
# NOTES        : EKS control plane తప్పదు కానీ మిగిలినవి minimal గా ఉంచాలి

# COST_AWARENESS.md - AWS Free Tier Mindful Build (Telugu)

# WARNING
AWS Free Tier అనే పేరు ఉన్నప్పటికీ **EKS Control Plane** కి monthly charge ఉంటుంది. Free Tier credits లేనిపక్షంలో బిల్లింగ్ వస్తుంది. పూర్తిగా zero కాదని గుర్తుంచుకో.

## 1) Expected Resources & Rough Cost Idea (Learning Purpose)
> *ఈ గణాంకాలు approx בלבד. Region, usage, time పై ఆధారపడి మారవచ్చు.*

| Resource | Count (Target) | Type/Size | Approx (us-east-1) | Notes (Telugu) |
| --- | --- | --- | --- | --- |
| **EKS Control Plane** | 1 | EKS Cluster | ~$0.10/hour (~$72/month) | **Avoid చేయలేము**. Work complete అయిన వెంటనే destroy చేయాలి |
| **EC2 Worker Nodes** | 1-2 | t3.small (Managed NG) | ~$0.0208/hour per node | Learning కోసం 1 node తో start చేసి అవసరమైతే 2 కి పెంచు |
| **NAT Gateway** | **1** | Single NAT | ~$0.045/hour + data processing | **Multi-AZ వద్దు**. 1 NAT తో వెళ్తాము (trade-off) |
| **EBS Volumes** | 2-3 | gp3 10-20GB | ~$0.08/GB-month (varies) | Postgres/Redis కి తక్కువ size ఇవ్వు |
| **ECR** | Few repos | Storage + pulls | Low (often small) | Images తగ్గుగా push చేయు |
| **Elastic IP (NAT)** | 1 | Attached to NAT | Usually free if attached; check | NAT కి attach అయ్యి ఉంటే check |
| **CloudWatch Logs** | Minimal | Basic logs | Can add up if verbose | Unnecessary logs avoid చేయు |

## 2) Free-Tier Rules We Follow
- [x] **Nodes:** `t3.small` only (bigger types వద్దు)
- [x] **NAT:** Max **1** NAT Gateway
- [x] **Node Count:** Start with **1** node. Scale up only if truly needed
- [x] **EBS:** Minimal (10GB gp3) per volume
- [x] **Monitoring:** kube-prometheus-stack install చేసినా resources తగ్గించు / test అయ్యాక options consider
- [x] **Cilium LB IPAM:** Use instead of AWS Load Balancer Controller (extra ALB/NLB avoid)
- [x] **Destroy Often:** Practice `terraform destroy` after learning session
- [x] **No NAT per AZ:** Strictly avoid

## 3) Cost Saving Tips (Telugu)
| Tip | Explanation |
| --- | --- |
| **Work in blocks** | ఒకసారి 2-4 గంటలు集中గా build చేసి ఆ session ముగిసిన వెంటనే teardown చేయడం ఉత్తమం |
| **Destroy after validation** | Phase complete అయ్యాక `05-scripts/teardown.sh` run చేసి check చేయి |
| **Stop thinking "keep running"** | EKS running ఉంటే గంటకి ఖర్చు. నేర్చుకోవడం + destroy = smart way |
| **Limit Hubble UI relay usage** | `kubectl port-forward` use చేసి leave చేయవద్దు unnecessarily |
| **Clean images** | ECR లో old images delete చేస్తూ ఉండు |
| **Watch NAT traffic** | NAT gateway ద్వారా outbound traffic cost వస్తుంది |

## 4) Daily Checklist Before/After
### Before Starting
- [ ] `00-docs/COST_AWARENESS.md` చూశాను
- [ ] `t3.small` use చేస్తున్నాను
- [ ] 1 NAT Gateway మాత్రమే
- [ ] Node count minimal

### After Finishing Session
- [ ] App validation complete
- [ ] `kubectl get nodes` check
- [ ] Plan to destroy OR explicitly keeping? (if keeping note reason)
- [ ] Run teardown if not needed next day

## 5) Teardown Reminder
**Always prefer teardown:** `cd 01-terraform-eks && terraform destroy -auto-approve` (platform uninstall + k8s cleanup తర్వాత మాత్రమే)

`05-scripts/teardown.sh` తయారు చేసి అదే use చేస్తాము.

**Last Note:** Enterprise mindset లో "Cost Optimization" అనేది architecture decision. మనం అదే practice చేస్తున్నాము.
