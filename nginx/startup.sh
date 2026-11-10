#!/bin/bash
# luna-nginx: a self-signed default certificate on first start (compose,
# minikube), the sites, then crond (logrotate) and nginx in the foreground.
set -e

if [ ! -f /etc/nginx/ssl/default.crt ]; then
    openssl genrsa -out "/etc/nginx/ssl/default.key" 2048
    openssl req -new -key "/etc/nginx/ssl/default.key" -out "/etc/nginx/ssl/default.csr" -subj "/CN=default/O=default/C=UK"
    openssl x509 -req -days 365 -in "/etc/nginx/ssl/default.csr" -signkey "/etc/nginx/ssl/default.key" -out "/etc/nginx/ssl/default.crt"
    chmod 644 /etc/nginx/ssl/default.key
fi

# Kubernetes (k8s/do): the sites come as templates; render the public host
# names into them (only these variables: nginx's own $variables stay), and
# reload every 6 hours so a certificate cert-manager renewed is picked up.
if compgen -G "/etc/nginx/templates/*.conf.template" > /dev/null; then
    command -v envsubst > /dev/null || { echo "startup.sh: envsubst is missing (it ships with nginx:alpine)" >&2; exit 1; }
    for t in /etc/nginx/templates/*.conf.template; do
        envsubst '${AUTH_HOST} ${DASHBOARD_HOST} ${WEBMAIL_HOST}' < "$t" \
            > "/etc/nginx/sites-available/$(basename "$t" .template)"
    done
    (while sleep 6h; do nginx -s reload; done) &
fi

crond -l 2 -b

# nginx.conf says `daemon off`: this stays in the foreground.
exec nginx
