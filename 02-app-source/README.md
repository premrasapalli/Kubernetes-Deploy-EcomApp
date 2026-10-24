# [TELUGU EXPLANATION]
# PURPOSE      : App source code folder
# WHAT IT DOES : Microservices source + Dockerfiles + build/push script
# WHY ENTERPRISE: App ని zero నుండి build చేసి ECR కి push చేయడం
# HOW TO USE   : Phase 1 app source + local smoke test
# NOTES        : Minimal working logic, clean structure

# 02-app-source/README.md

## Folder Purpose (లక్ష్యం)
ఈ folder లో **retailx** app యొక్క source code మొత్తం ఉంటాది.

మనం app ని readyగా తీసుకోకూడదు - **zero నుండి write** చేస్తాము.

## Services
| Service | Tech | Purpose (Telugu) |
| --- | --- | --- |
| **frontend** | Nginx + HTML/JS | UI - Product list, Cart, Order form |
| **product-api** | Node.js (Express) | Product catalog API - Postgres నుండి read |
| **cart-api** | Node.js (Express) | Cart API - Redis ని use చేస్తుంది |
| **order-api** | Node.js (Express) | Order API - Postgres కి write |

## Structure
```text
02-app-source/
├── frontend/           # index.html, app.js, styles.css, Dockerfile
│                       # nginx.local.conf (local compose proxy only)
├── product-api/        # src/index.js, package.json, package-lock.json, Dockerfile
├── cart-api/           # src/index.js, package.json, package-lock.json, Dockerfile
├── order-api/          # src/index.js, package.json, package-lock.json, Dockerfile
└── docker-compose.yml  # Phase 1 local smoke test (Postgres + Redis + 4 services)
```

## Goals
- **Minimal but testable** - Health endpoints, basic CRUD enough
- **Containerized** - ప్రతి service కి Dockerfile
- **ECR ready** - `../05-scripts/02-build-push.sh` ద్వారా build + push
- **Locally testable** - `docker-compose.yml` + `../05-scripts/05-local-smoke.sh`
- **Telugu explained** - ప్రతి file కి explanation

## Local run (AWS ఖర్చు లేదు)
```bash
./05-scripts/05-local-smoke.sh          # build, up, curl products/cart/orders, down
KEEP_UP=1 ./05-scripts/05-local-smoke.sh # తర్వాత inspect చేయడానికి stack నిలిపి ఉంచుతుంది
./05-scripts/05-local-smoke.sh --down   # stack మాత్రమే తీసేయడం
```
`http://localhost:8080` — `nginx.local.conf` `/api/*` ని సేవలకు proxy చేస్తుంది.
EKS లో ఇదే పని Gateway API HTTPRoute చేస్తుంది; ఆ config ఇమేజ్‌లో ఉండదు.

## Notes
- Secrets hardcode చేయకూడదు (later env/ExternalSecrets)
- Lightweight base images use చేయడం better (node:slim, nginx:alpine) - size తగ్గించేందుకు
- Logs simple గా ఉంచి debug easy గా

**Phase 1 పూర్తయింది.** వివరణ: `docs/te/06-phase-1-app-source.md`.
