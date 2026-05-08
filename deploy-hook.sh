#!/bin/bash
# Creates second Nginx vhost for Uptime Kuma at status.vps.sarvinshrivastava.space

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
