# ── తెలుగు వివరణ ─────────────────────────────────────────────
# cart-api ఇమేజ్: Redis క్లయింట్ తో; non-root node user; PSS restricted compatible.
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
EXPOSE 8082
CMD ["node", "src/index.js"]
