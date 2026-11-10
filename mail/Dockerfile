FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postfix \
        dovecot-core \
        dovecot-imapd \
        dovecot-lmtpd \
        mailutils \
        supervisor \
        gettext-base \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY postfix/main.cf.template  /etc/postfix/main.cf.template
COPY postfix/master.cf         /etc/postfix/master.cf
COPY dovecot/dovecot.conf.template /etc/dovecot/dovecot.conf.template
COPY supervisord.conf /etc/supervisor/conf.d/mail.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 25 — приём почты (SMTP), 587 — авторизованная отправка (Submission),
# 993 — IMAP/TLS, если захотите читать почту почтовым клиентом.
EXPOSE 25 587 993

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
