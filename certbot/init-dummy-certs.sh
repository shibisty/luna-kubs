#!/bin/sh
set -e

apk add --no-cache openssl >/dev/null

: "${AUTH_DOMAIN:?}"
: "${DASHBOARD_DOMAIN:?}"
: "${MAIL_DOMAIN:?}"

for DOMAIN in "$AUTH_DOMAIN" "$DASHBOARD_DOMAIN" "$MAIL_DOMAIN"; do
    if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        echo "No cert for ${DOMAIN} yet — creating a throwaway self-signed one so nginx can start."
        mkdir -p "/etc/letsencrypt/live/${DOMAIN}"
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -subj "/CN=${DOMAIN}" \
            -keyout "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" \
            -out "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    else
        echo "Cert for ${DOMAIN} already present, leaving it alone."
    fi
done
