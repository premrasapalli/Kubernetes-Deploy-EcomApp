# ── తెలుగు వివరణ ─────────────────────────────────────────────
# product-api ఇమేజ్: multi-stage build, ప్రొడక్షన్ డిపెండెన్సీలు మాత్రమే,
# non-root user (node, UID 1000), చిన్న alpine ఆధారం. PSS restricted కి సిద్ధం.
# ─────────────────────────────────────────────────────────────
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src
USER node
EXPOSE 8081
CMD ["node", "src/index.js"]
