# The edge of the stack: TLS and the virtual hosts in sites/ (mounted at
# /etc/nginx/sites-available). startup.sh creates a self-signed default.crt
# in /etc/nginx/ssl on first start, then runs crond (logrotate) and nginx.
FROM nginx:alpine

RUN apk add --no-cache bash logrotate openssl \
 && { grep -q '^www-data:' /etc/group || addgroup -g 82 -S www-data; } \
 && { grep -q '^www-data:' /etc/passwd || adduser -u 82 -D -S -G www-data www-data; } \
 && touch /var/log/messages \
 && rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/
COPY logrotate/nginx /etc/logrotate.d/
COPY startup.sh /opt/startup.sh
RUN sed -i 's/\r//g' /opt/startup.sh

EXPOSE 80 443
CMD ["/bin/bash", "/opt/startup.sh"]
