# Phase 1 — App Source (retailx microservices)

> ఇంగ్లీష్ సారాంశం: `02-app-source/README.md`, `docs/ARCHITECTURE.md`.
> Phase 1 లో AWS ఖర్చు $0 — అంతా local Docker తోనే verify చేస్తాము.

## లక్ష్యం
retailx app ని ready గా తీసుకోకుండా zero నుండి రాయడం: frontend + 3 APIs +
Dockerfiles + local smoke test. ఇవే ఇమేజ్‌లు Phase 2 తర్వాత ECR కి వెళ్తాయి,
Phase 4 లో K8s workloads గా నడుస్తాయి.

## ఫైల్‌లు ఒక్కొక్కటి

### `frontend/`
- `index.html` — Products, Cart, Orders అనే మూడు sections. JS ద్వారా data load.
- `app.js` — `/api/products`, `/api/cart/demo`, `/api/orders?userId=demo` కి fetch.
  - ప్రతి product card లో **Add to cart** + **Place order** బటన్లు.
  - `placeOrder()` ఇప్పుడు బటన్‌కు కనెక్ట్ అయింది (ముందు వాడకుండా ఉండేది).
  - `$("clear-cart")` — `DELETE /api/cart/demo`.
- `styles.css` — dark theme, `.secondary` బటన్ స్టైల్.
- `Dockerfile` — `nginxinc/nginx-unprivileged:1.27-alpine`, UID 101, port 8080.
- `nginx.local.conf` — **local compose కోసం మాత్రమే** `/api/*` ని సేవల DNS పేర్లకు
  proxy చేస్తుంది. EKS లో ఈ పని Gateway API HTTPRoute చేస్తుంది, కాబట్టి ఇది
  ఇమేజ్‌లోకి copy అవ్వదు (compose లో mount మాత్రమే).

### `product-api/`
- `src/index.js` — Express + `pg` Pool. Port `8081`.
  - `initSchema()` — `products` table create చేసి, ఖాళీగా ఉంటే 3 sample products insert.
  - `/health` — schema ready అయ్యే వరకు `503`, తర్వాత `SELECT 1` check.
  - `GET /api/products`, `GET /api/products/:id`, `POST /api/products`.
  - `SIGTERM` పై `pool.end()` — graceful shutdown.
- `package.json` / `package-lock.json` — `express`, `pg`. Lock ఉన్నందుకే `npm ci` reliable.
- `Dockerfile` — multi-stage: `deps` లో `npm ci --omit=dev`, final లో `USER node`.

### `cart-api/`
- `src/index.js` — Express + `redis` client. Port `8082`.
  - Cart ఒక Redis hash: key `cart:<userId>`, field = productId, value = quantity.
  - `GET /api/cart/:userId`, `POST /api/cart/:userId/items` (`hIncrBy`),
    `DELETE /api/cart/:userId`.
  - `/health` — `PING` విజయవంతమైతే `ok`.
  - reconnect strategy + 30 retry loop — Redis ముందు లేచినా crash అవ్వదు.

### `order-api/`
- `src/index.js` — Express + `pg` Pool. Port `8083`.
  - `orders` table: id, user_id, product_id, quantity, status, created_at.
  - `POST /api/orders`, `GET /api/orders/:id`, `GET /api/orders?userId=`.
  - `/health` — `SELECT 1`.
  - `SIGTERM` పై graceful shutdown.

### `docker-compose.yml` (local only)
- `postgres:16-alpine`, `redis:7-alpine` + healthchecks.
- సేవా పేర్లు `product-api`, `cart-api`, `order-api`, `frontend` — K8s Service పేర్లతో సమానం.
- APIs `depends_on: condition: service_healthy`; frontend APIలు healthy అయ్యాక start.
- Credentials **local dummy** మాత్రమే (`retailx-local`); cloud లో External Secrets.
- `pgdata` named volume — container recreate అయినా data ఉంటుంది.

### `05-scripts/02-build-push.sh`
- నాలుగు ఇమేజ్‌లను `--platform linux/amd64` తో build చేసి ECR కి push.
- `TAG` డిఫాల్ట్ `v1`; ప్రొడక్షన్‌లో immutable git SHA వాడాలి.
- ECR repo names `retailx/<service>` — `01-terraform-eks/ecr.tf` తో match అవుతాయి.

### `05-scripts/05-local-smoke.sh`
- compose stack build + up, readiness కోసం poll, తర్వాత:
  products list → cart add → cart read → order create → orders list.
- Default గా test తర్వాత `down -v` (ఖర్చు/డిస్క్ cleanup). `KEEP_UP=1` తో నిలిపి ఉంచవచ్చు.

## ఎందుకు ఈ విలువలు (design decisions)

- **Port 8080 (nginx)** = unprivileged image default; 80 కి bind చేయాలంటే root కావాలి,
  PSS `restricted` అందుకు ఒప్పుకోదు.
- **UID 101 (nginx), UID 1000 (`node`)** = image డిఫాల్ట్ non-root users; K8s
  `runAsNonRoot` తో ఘర్షణ ఉండదు.
- **multi-stage + `npm ci --omit=dev`** = dev dependencies ఇమేజ్‌లోకి వెళ్లవు;
  ఇమేజ్ చిన్నది, CVE surface తక్కువ, lockfile కి bind అవుతుంది.
- **`/health` వేరుగా, `/` కాదు** = probes కి ఖచ్చితమైన సిగ్నల్; DB/Redis down ఉంటే
  readiness fail అవ్వాలి, కానీ process చచ్చిపోకూడదు.
- **30 × 3s retry loops** = pod start ordering race ని తట్టుకోవడం; K8s restart backoff
  తో కలిపి మొదటి rollout లో crash-loop శబ్దం తగ్గుతుంది.
- **DB credentials env నుండి** = hardcode చేయలేదు; Phase 4 లో Secret/ExternalSecret.
- **Postgres service headless, Redis headless** (Phase 4) = stable network identity;
  app కి మాత్రం `postgres:5432`, `redis:6379` అనే పేర్లే కనిపిస్తాయి.
- **user `demo`** = single-user demo; నిజమైన auth Phase 6 hardening కి వదిలాం.

## సాధారణ తప్పులు

1. `DB_PASSWORD` ఇవ్వకపోవడం → `pg` auth error → Secret/env నుండి ఇవ్వాలి.
2. `nginx:alpine` (root, port 80) వాడటం → PSS restricted reject → unprivileged image.
3. `npm install` వాడటం → lockfile drift → ఇమేజ్‌లో `npm ci`.
4. Redis/Postgres ముందు లేకపోతే ప్రారంభంలోనే crash → retry loop + healthcheck.
5. `POST /api/orders` కి `userId` పంపకపోవడం → `400` → `{userId, productId, quantity}`.
6. Local లో `/api/*` కి `404` → Gateway లేదు → compose లో `nginx.local.conf` proxy వాడాలి.
7. frontend `/api` requests ని `http://localhost:8081` అని hardcode చేయడం → browser
   నుండి EKS Service reachable కాదు → same-origin `/api` + Gateway/nginx routing.

## ధృవీకరణ

```bash
# 1) local end-to-end (AWS ఖర్చు లేదు)
./05-scripts/05-local-smoke.sh

# 2) image build మాత్రమే
docker build -t retailx/product-api:test 02-app-source/product-api
docker run --rm retailx/product-api:test node -e "console.log('ok')"

# 3) Phase 2 తర్వాత ECR push
TAG=v1 ./05-scripts/02-build-push.sh
```

ఆశించిన ఫలితం: smoke script లో products JSON, cart hash, order JSON వస్తాయి;
చివర్లో `OK: products, cart and orders all responded over the frontend proxy.`

## సంబంధిత ఇష్యూలు

- ఇంకా నిజమైన failure log లేదు. Phase 4/5 లో app-related issues వస్తే
  `docs/ISSUES.md` + `docs/te/issues/` లో నమోదు చేయాలి.
