#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/kittygram"
SECRET=$(openssl rand -hex 32)
PGPASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
sed -i "s#^POSTGRES_PASSWORD=.*#POSTGRES_PASSWORD=${PGPASS}#" .env
sed -i "s#^SECRET_KEY=.*#SECRET_KEY=${SECRET}#" .env

if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 || \
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

DC=(sudo docker compose)
"${DC[@]}" -f docker-compose.production.yml pull
"${DC[@]}" -f docker-compose.production.yml up -d
sleep 25
"${DC[@]}" -f docker-compose.production.yml exec -T backend python manage.py migrate
"${DC[@]}" -f docker-compose.production.yml exec -T backend python manage.py collectstatic --noinput
"${DC[@]}" -f docker-compose.production.yml ps
