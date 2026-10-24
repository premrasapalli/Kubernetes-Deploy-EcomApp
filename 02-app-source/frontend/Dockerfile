# ── తెలుగు వివరణ ─────────────────────────────────────────────
# frontend: unprivileged nginx (UID 101, port 8080). root అవసరం లేదు,
# PSS restricted కి సిద్ధం. static files మాత్రమే serve చేస్తుంది.
# ─────────────────────────────────────────────────────────────
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY index.html app.js styles.css /usr/share/nginx/html/
EXPOSE 8080
