#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Nginx vhost for Uptime Kuma ─────────────────────────────────────────────
UPTIME_VHOST="/etc/nginx/sites-available/status.vps"
if [ ! -f "$UPTIME_VHOST" ]; then
  cat > "$UPTIME_VHOST" << 'EOF'
server {
    listen 80;
    server_name status.vps.sarvinshrivastava.space;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name status.vps.sarvinshrivastava.space;
    include snippets/ssl-vps.conf;
    location / {
        proxy_pass http://localhost:3101;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
  ln -sf "$UPTIME_VHOST" /etc/nginx/sites-enabled/status.vps
  echo "Created Uptime Kuma vhost"
fi
nginx -t && systemctl reload nginx

# ── Wait for Uptime Kuma to accept connections ───────────────────────────────
echo "Waiting for Uptime Kuma..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:3101 > /dev/null 2>&1; then
    echo "Uptime Kuma ready"
    break
  fi
  sleep 2
done

# ── Create monitors via socket.io ────────────────────────────────────────────
if command -v node &>/dev/null && [ -f "$SCRIPT_DIR/uptime-setup.mjs" ]; then
  cd "$SCRIPT_DIR"
  # Read Grafana password from .env (same password used for Uptime Kuma)
  if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
  fi
  export UK_PASSWORD="${GRAFANA_PASSWORD:-}"
  npm install --silent 2>/dev/null
  node uptime-setup.mjs
else
  echo "WARNING: node or uptime-setup.mjs missing — skipping monitor setup"
fi

# ── Status page + group setup via SQLite ─────────────────────────────────────
UK="docker exec uptime-kuma sqlite3 /app/data/kuma.db"

# Wait for DB
for i in $(seq 1 15); do
  if $UK "SELECT 1;" > /dev/null 2>&1; then break; fi
  sleep 2
done

SP_SLUG="sarvin-vps"
SP_TITLE="VPS Status"

SP_ID=$($UK "SELECT id FROM status_page WHERE slug='$SP_SLUG' LIMIT 1;" 2>/dev/null || true)
if [ -z "$SP_ID" ]; then
  $UK "INSERT INTO status_page (slug, title, description, icon, theme, published, search_engine_index, show_tags, password, footer_text, custom_css, show_powered_by, google_analytics_tag_id, show_certificate_expiry) VALUES ('$SP_SLUG', '$SP_TITLE', '', '/icon.svg', 'light', 1, 1, 0, NULL, NULL, NULL, 1, NULL, 0);"
  SP_ID=$($UK "SELECT id FROM status_page WHERE slug='$SP_SLUG';")
  echo "Created status page (id=$SP_ID)"
else
  echo "Status page already exists (id=$SP_ID)"
fi

GRP_ID=$($UK "SELECT id FROM 'group' WHERE status_page_id=$SP_ID LIMIT 1;" 2>/dev/null || true)
if [ -z "$GRP_ID" ]; then
  $UK "INSERT INTO 'group' (name, created_date, public, active, weight, status_page_id) VALUES ('Services', datetime('now'), 1, 1, 1000, $SP_ID);"
  GRP_ID=$($UK "SELECT id FROM 'group' WHERE status_page_id=$SP_ID;")
  echo "Created group (id=$GRP_ID)"
else
  $UK "UPDATE 'group' SET public=1 WHERE id=$GRP_ID;"
  echo "Group already exists (id=$GRP_ID)"
fi

# Add each monitor to the group (idempotent)
while IFS= read -r MID; do
  [ -z "$MID" ] && continue
  EXISTS=$($UK "SELECT COUNT(*) FROM monitor_group WHERE monitor_id=$MID AND group_id=$GRP_ID;")
  if [ "$EXISTS" = "0" ]; then
    $UK "INSERT INTO monitor_group (monitor_id, group_id, weight, send_url) VALUES ($MID, $GRP_ID, 1000, 0);"
    echo "Added monitor $MID to group"
  fi
done < <($UK "SELECT id FROM monitor;")

echo "Uptime Kuma setup complete"
