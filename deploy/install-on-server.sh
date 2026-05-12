#!/usr/bin/env bash
# Запускать НА СЕРВЕРЕ после ssh (не в PowerShell на Windows).
# Перед запуском: scp deploy/*.conf deploy/install-on-server.sh ubuntu@81.26.183.233:~/
#
# Настройка порта Taski (если не 8000 — поменяйте одну строку):
TASKI_PORT="${TASKI_PORT:-8000}"

set -euo pipefail

KITTY_HOST="mykittygramqqqwww.hopto.org"
TASKI_HOST="mytaski.myftp.org"
HOME_DIR="${HOME}"

echo "==> UFW (22, 80, 443)"
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
yes | sudo ufw enable || true

echo "==> Kittygram Docker (~/kittygram)"
if [[ -f "${HOME_DIR}/kittygram/docker-compose.production.yml" ]]; then
  cd "${HOME_DIR}/kittygram"
  docker compose -f docker-compose.production.yml pull
  docker compose -f docker-compose.production.yml up -d
  docker compose -f docker-compose.production.yml exec -T backend python manage.py migrate || true
  docker compose -f docker-compose.production.yml exec -T backend python manage.py collectstatic --noinput || true
else
  echo "Нет ~/kittygram/docker-compose.production.yml — создайте папку, положите compose и .env, затем перезапустите скрипт."
fi

echo "==> Nginx vhosts"
sudo tee /etc/nginx/sites-available/kittygram.conf >/dev/null <<EOF
server {
    listen 80;
    server_name ${KITTY_HOST};
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOF

sudo tee /etc/nginx/sites-available/taski.conf >/dev/null <<EOF
server {
    listen 80;
    server_name ${TASKI_HOST};
    location / {
        proxy_pass http://127.0.0.1:${TASKI_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/kittygram.conf /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/taski.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo "==> Certbot (нужен email; можно задать: export CERTBOT_EMAIL=you@mail.com)"
if ! command -v certbot >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y certbot python3-certbot-nginx
fi
EMAIL="${CERTBOT_EMAIL:-admin@localhost}"
sudo certbot --nginx -d "${KITTY_HOST}" -d "${TASKI_HOST}" --non-interactive --agree-tos -m "${EMAIL}" || {
  echo "Certbot не смог выпустить сертификат (DNS ещё не дошёл или порт 80 закрыт). Повторите позже:"
  echo "  sudo certbot --nginx -d ${KITTY_HOST} -d ${TASKI_HOST}"
}

echo "==> Проверка локально на сервере"
curl -sI "http://127.0.0.1:9000/" | head -n 1 || true
curl -sI "https://${KITTY_HOST}/" | head -n 1 || true
curl -sI "https://${TASKI_HOST}/" | head -n 1 || true

echo "Готово."
