# Exoforge Staging Deployment Guide (Arch Linux VPS)

This document provides complete, reproducible instructions for an AI agent (such as Antigravity) or developer to configure, boot, and maintain a continuously updating staging environment on an Arch Linux VPS.

---

## 1. System Prerequisites on Arch Linux

Run as `root` or user with `sudo`:

```bash
# 1. Update system packages
pacman -Syu --noconfirm

# 2. Install runtime tools (Docker, Compose, Caddy reverse proxy, git, curl)
pacman -S --noconfirm docker docker-compose caddy git curl jq ufw

# 3. Create a 4GB swapfile (vital to prevent BEAM/Postgres OOM on low-RAM VPS)
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi

# 4. Enable and start Docker & Caddy system services
systemctl enable --now docker
systemctl enable --now caddy
```

---

## 2. Firewall & Network Hardening

Exoforge exposes Studio (:4005), WebSockets (:4000), REST API (:4001), and PostgreSQL (:5432).
**Never expose these raw ports publicly.** Expose only SSH, HTTP, and HTTPS; let Caddy handle internal reverse proxying.

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp     # SSH
ufw allow 80/tcp     # HTTP (Let's Encrypt challenges)
ufw allow 443/tcp    # HTTPS & WSS
ufw --force enable
```

---

## 3. Clone Repository & Setup Directory

Recommended working directory: `/opt/exoforge`

```bash
# Create directory and clone
mkdir -p /opt/exoforge
cd /opt/exoforge

# Clone repository if not already present
if [ ! -d ".git" ]; then
  git clone https://github.com/alxcsx/exoforge.git .
fi

git checkout projetao_mvp
```

---

## 4. Environment Configuration (`.env`)

Generate cryptographically secure secrets and write `/opt/exoforge/.env`:

```bash
cat << 'EOF' > /opt/exoforge/.env
# Database Credentials
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=exoforge_prod

# Exoforge Security Secrets
SECRET_KEY_BASE=$(openssl rand -base64 48)
LIVEVIEW_SIGNING_SALT=$(openssl rand -base64 16)
RELEASE_COOKIE=$(openssl rand -hex 16)

# Host & Admin
PHX_HOST=localhost
EXOFORGE_ADMIN_EMAIL=admin@staging.exoforge.local
EXOFORGE_ADMIN_PASSWORD=$(openssl rand -hex 12)

# Ports
PORT=4005
DASHBOARD_PORT=4005
GATEWAY_PORT=4000
HTTP_PORT=4001
EOF
```

> [!NOTE]
> Review generated admin credentials: `grep EXOFORGE_ADMIN /opt/exoforge/.env`

---

## 5. Reverse Proxy Configuration (`/etc/caddy/Caddyfile`)

Caddy automatically provisions and renews SSL/TLS certificates and handles WebSocket connection upgrading natively.

Replace `staging.yourdomain.com` with your actual domain or subdomains:

```caddy
# /etc/caddy/Caddyfile

# Studio LiveView UI
studio.staging.yourdomain.com {
    reverse_proxy 127.0.0.1:4005
}

# WebSocket Gateway (Game clients)
ws.staging.yourdomain.com {
    reverse_proxy 127.0.0.1:4000
}

# REST API Ingress
api.staging.yourdomain.com {
    reverse_proxy 127.0.0.1:4001
}
```

Reload Caddy:
```bash
systemctl reload caddy
```

---

## 6. Booting the Stack

### Option A: Pull Pre-built Image from GHCR (Fastest, zero VPS CPU overhead)
Once the GitHub CI/CD pipeline pushes images to `ghcr.io/alxcsx/exoforge:staging`:

```bash
# Pull and start services
docker compose pull backend
docker compose up -d --remove-orphans
```

### Option B: Build Image Locally on VPS
If testing without the remote registry:

```bash
docker compose up -d --build
```

---

## 7. Verification & Health Probes

Verify all containers and endpoints are healthy:

```bash
# 1. Check container health status
docker compose ps

# 2. Verify backend internal healthcheck (HTTP 200)
curl -fsS http://127.0.0.1:4005/health
# Output should be: OK or {"status":"healthy"}

# 3. Inspect application logs
docker compose logs --tail=50 backend
```

---

## 8. Automated Continuous Deployment (Trigger on Git Commit)

To update the staging environment as soon as a commit lands on the remote repository:

### Method 1: Lightweight Webhook (Recommended)

1. Install `webhook`:
   ```bash
   pacman -S --noconfirm webhook
   ```

2. Create `/etc/webhook/hooks.json`:
   ```json
   [
     {
       "id": "deploy-staging",
       "execute-command": "/opt/exoforge/deploy/update-staging.sh",
       "command-working-directory": "/opt/exoforge",
       "response-message": "Deployment initiated",
       "trigger-rule": {
         "match": {
           "type": "value",
           "value": "CHANGE_TO_YOUR_SHARED_SECRET_TOKEN",
           "parameter": {
             "type": "header",
             "name": "X-Hub-Signature"
           }
         }
       }
     }
   ]
   ```

3. Enable webhook daemon:
   ```bash
   systemctl enable --now webhook
   ```

4. Configure GitHub Repository Secrets (**Settings ▸ Secrets and variables ▸ Actions**):
   - `STAGING_DEPLOY_WEBHOOK_URL`: `https://staging.yourdomain.com:9000/hooks/deploy-staging`
   - `STAGING_DEPLOY_WEBHOOK_SECRET`: The token string matching the rule above.

### Method 2: Systemd Pull Timer (Self-contained Polling)

If you prefer not exposing a webhook port, use a systemd timer that checks for updates every 2 minutes:

Create `/etc/systemd/system/exoforge-staging.service`:
```ini
[Unit]
Description=Exoforge Staging Auto-Update
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/exoforge
ExecStart=/opt/exoforge/deploy/update-staging.sh
```

Create `/etc/systemd/system/exoforge-staging.timer`:
```ini
[Unit]
Description=Run Exoforge Staging Update every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
```

Enable timer:
```bash
systemctl daemon-reload
systemctl enable --now exoforge-staging.timer
```

---

## 9. Maintenance & Data Hygiene

Integration tests continuously register disposable accounts. Purge them periodically:

```bash
docker exec exoforge_backend /app/bin/exoforge eval "Exoforge.ActionDispatcher.dispatch(:auth, :purge_disposable, %{})"
```

To wipe and reset dev/staging databases completely:
```bash
docker compose down -v
docker compose up -d
```
