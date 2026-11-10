#!/bin/sh
set -e

: "${AUTH_DOMAIN:?AUTH_DOMAIN env var is required}"
: "${DASHBOARD_DOMAIN:?DASHBOARD_DOMAIN env var is required}"
: "${MAIL_DOMAIN:?MAIL_DOMAIN env var is required}"
: "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL env var is required}"

# Один сертификат на каждый домен по отдельности (проще ротировать/отзывать
# по одному, чем разбираться с SAN-сертификатом на всех сразу).
for DOMAIN in "$AUTH_DOMAIN" "$DASHBOARD_DOMAIN" "$MAIL_DOMAIN"; do
    # /etc/letsencrypt/live/$DOMAIN/fullchain.pem может существовать и быть
    # самоподписанной заглушкой (см. init-dummy-certs.sh) — единственный
    # надёжный признак того, что сертификат РЕАЛЬНО выпущен certbot'ом,
    # это наличие его renewal-конфига.
    if [ ! -f "/etc/letsencrypt/renewal/${DOMAIN}.conf" ]; then
        echo "Requesting certificate for ${DOMAIN}..."
        # Заглушка из init-dummy-certs.sh не отслеживается certbot'ом
        # (нет renewal-конфига) — просто мешает, удаляем перед реальным запросом.
        rm -rf "/etc/letsencrypt/live/${DOMAIN}" "/etc/letsencrypt/archive/${DOMAIN}"
        certbot certonly \
            --webroot -w /var/www/certbot \
            --email "$LETSENCRYPT_EMAIL" \
            --agree-tos \
            --no-eff-email \
            -d "$DOMAIN" \
            --non-interactive || echo "WARNING: failed to obtain cert for ${DOMAIN} — is its DNS A-record pointing here yet?"
    else
        echo "Certificate for ${DOMAIN} already exists, skipping initial issuance."
    fi
done

# Дальше — бесконечный цикл продления (certbot сам не продлевает раньше,
# чем нужно — команда renew безопасна вызывать хоть каждый час).
while :; do
    certbot renew --webroot -w /var/www/certbot --quiet
    sleep 12h
done
