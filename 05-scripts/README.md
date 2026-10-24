# [TELUGU EXPLANATION]
# PURPOSE      : Automation scripts folder
# WHAT IT DOES : bootstrap/validate/teardown scripts
# WHY ENTERPRISE: Repeatable & safe automation
# HOW TO USE   : Phase 5/7 లో use చేస్తాము
# NOTES        : Safe checks, clear messages in Telugu+English, cost aware

# 05-scripts/README.md

## Folder Purpose (లక్ష్యం)
ఈ folder లో end-to-end automation కోసం scripts ఉంచుతాము.

**bootstrap**, **validate**, **teardown** - ఇవే మూడు main scripts.

## Scripts
| Script | Purpose (Telugu) | When to use |
| --- | --- | --- |
| **bootstrap.sh** | Full flow guide/automation - check prereqs, remind order | Starting fresh (Phase 5 తరువాత refine) |
| **validate.sh** | Health checks - nodes, pods, gateway, policies, DNS | After deploy, before marking done |
| **teardown.sh** | Safe teardown order - k8s -> platform -> terraform | **Session end / Free-Tier save** |

## Design Principles
- **Idempotent where possible** - mehrfach run చేసినా major damage కాకుండా
- **Fail fast** - `set -euo pipefail`
- **Telugu messages** - User కి అర్థం అయ్యేలా
- **Cost aware** - teardown remind చేస్తుంది
- **Dry run mindset** - destructive cmds కి confirmation (teardown)
- **Log clearly** - step by step print

## Usage (Future)
```bash
# Validate after deployment
./05-scripts/validate.sh

# Teardown at end of session
./05-scripts/teardown.sh
```

## Notes
- Scripts లో hardcoded values minimize చేసి variables use చేస్తాము
- AWS CLI, kubectl, helm, terraform, cilium CLI అవసరం
- `teardown.sh` మాత్రం **extra caution** తో రాస్తాము

**Scripts** create చేయడం Phase 7 లో intensify అవుతుంది కానీ structure ఇప్పుడే సిద్ధం.
