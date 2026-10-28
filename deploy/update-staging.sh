#!/usr/bin/env bash
set -euo pipefail

# Move to exoforge directory
cd "$(dirname "$0")/.."

echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Starting Exoforge staging update..."

# Pull git changes
git fetch origin projetao_mvp
git reset --hard origin/projetao_mvp

# Pull new Docker images or rebuild
if docker compose pull backend 2>/dev/null; then
  echo "Pulled latest image from registry."
else
  echo "Pull failed or using local build; rebuilding containers..."
  docker compose build backend
fi

# Recreate containers with minimal downtime
docker compose up -d --remove-orphans backend

# Wait for healthy endpoint
HEALTHY=false
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:4005/health > /dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 1
done

if [ "$HEALTHY" = true ]; then
  echo "Exoforge staging backend is healthy."
  # Optional: Purge disposable test accounts left over from integration runs
  docker compose exec -T backend /app/bin/exoforge eval "Exoforge.ActionDispatcher.dispatch(:auth, :purge_disposable, %{})" >/dev/null 2>&1 || true
  exit 0
else
  echo "ERROR: Health check failed on http://127.0.0.1:4005/health" >&2
  docker compose logs --tail=50 backend >&2
  exit 1
fi
