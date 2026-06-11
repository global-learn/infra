#!/bin/sh
# ---------------------------------------------------------------------------
# Run ONCE on the server to obtain the first Let's Encrypt certificate.
#
# Prerequisites:
#   - DOMAIN and ACME_EMAIL are filled in .env
#   - the domain's DNS A-record points at THIS server
#   - ports 80 and 443 are open
#
# Usage:  chmod +x init-letsencrypt.sh && ./init-letsencrypt.sh
#
# After it succeeds, start the rest of the stack with:  docker compose up -d
# Renewals happen automatically afterwards (certbot service), no need to re-run.
# ---------------------------------------------------------------------------
set -e

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run: cp .env.example .env  and fill it in."
  exit 1
fi

# load DOMAIN / ACME_EMAIL / CERTBOT_STAGING from .env
. ./.env

if [ -z "$DOMAIN" ] || [ -z "$ACME_EMAIL" ]; then
  echo "ERROR: set DOMAIN and ACME_EMAIL in .env"
  exit 1
fi

staging="${CERTBOT_STAGING:-0}"
cert_path="/etc/letsencrypt/live/$DOMAIN"

echo "### 1/5 Pulling images ..."
docker compose pull

echo "### 2/5 Creating a temporary self-signed certificate for $DOMAIN ..."
# nginx needs *some* certificate to start before the real one exists
docker compose run --rm --entrypoint "\
  sh -c 'mkdir -p $cert_path && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout $cert_path/privkey.pem \
    -out $cert_path/fullchain.pem \
    -subj /CN=localhost'" certbot

echo "### 3/5 Starting nginx ..."
docker compose up --force-recreate -d nginx

echo "### 4/5 Replacing the temporary certificate with a real one ..."
docker compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$DOMAIN \
         /etc/letsencrypt/archive/$DOMAIN \
         /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

staging_arg=""
if [ "$staging" != "0" ]; then
  echo "    (using Let's Encrypt STAGING — certificate will NOT be trusted by browsers)"
  staging_arg="--staging"
fi

docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    --email $ACME_EMAIL \
    -d $DOMAIN \
    --agree-tos \
    --no-eff-email \
    --force-renewal" certbot

echo "### 5/5 Reloading nginx ..."
docker compose exec nginx nginx -s reload

echo ""
echo "Done. Now bring up the whole stack:  docker compose up -d"
echo "Then open:  https://$DOMAIN"
