#!/bin/sh
set -e

: "${MAIL_DOMAIN:?MAIL_DOMAIN env var is required}"
: "${MAIL_USERNAME:?MAIL_USERNAME env var is required (e.g. noreply)}"
: "${MAIL_PASSWORD:?MAIL_PASSWORD env var is required}"

export MAIL_DOMAIN

# TLS files: certbot's by default (compose), cert-manager's Secret in Kubernetes.
: "${MAIL_TLS_CERT:=/etc/letsencrypt/live/${MAIL_DOMAIN}/fullchain.pem}"
: "${MAIL_TLS_KEY:=/etc/letsencrypt/live/${MAIL_DOMAIN}/privkey.pem}"
export MAIL_TLS_CERT MAIL_TLS_KEY

# --- Сертификаты ---
# main.cf/dovecot.conf ссылаются на /etc/letsencrypt/live/$MAIL_DOMAIN/*.
# При самом первом запуске (до того как certbot вообще успел отработать)
# этих файлов ещё не существует — postfix/dovecot просто не стартанут.
# Кладём временный self-signed сертификат, чтобы сервисы поднялись; после
# первого успешного certbot-релиза (см. сервис certbot в docker-compose)
# реальный сертификат окажется по тому же пути и его подхватят при рестарте.
CERT_DIR="/etc/letsencrypt/live/${MAIL_DOMAIN}"
# if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
#     echo "No Let's Encrypt cert yet for ${MAIL_DOMAIN} — generating a temporary self-signed one."
#     mkdir -p "${CERT_DIR}"
#     openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
#         -subj "/CN=${MAIL_DOMAIN}" \
#         -keyout "${CERT_DIR}/privkey.pem" \
#         -out "${CERT_DIR}/fullchain.pem"
# fi

# --- Подстановка домена в конфиги ---
envsubst '${MAIL_DOMAIN} ${MAIL_TLS_CERT} ${MAIL_TLS_KEY}' < /etc/postfix/main.cf.template > /etc/postfix/main.cf
envsubst '${MAIL_DOMAIN} ${MAIL_TLS_CERT} ${MAIL_TLS_KEY}' < /etc/dovecot/dovecot.conf.template > /etc/dovecot/dovecot.conf

# --- Почтовый пользователь (dovecot passwd-file) ---
mkdir -p "/var/mail/vhosts/${MAIL_DOMAIN}/${MAIL_USERNAME}"
if [ ! -f /etc/dovecot/users ]; then
    HASH=$(doveadm pw -s SHA512-CRYPT -p "${MAIL_PASSWORD}")
    echo "${MAIL_USERNAME}@${MAIL_DOMAIN}:${HASH}::::::" > /etc/dovecot/users
fi
chown -R dovecot:dovecot /var/mail/vhosts /etc/dovecot/users
chmod 600 /etc/dovecot/users

# --- Postfix требует свою chroot-структуру и владельцев на первом старте ---
postfix set-permissions 2>/dev/null || true
mkdir -p /var/spool/postfix/private
newaliases || true

exec "$@"
