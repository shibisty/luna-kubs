ARG POSTGRES_VERSION=18-alpine
FROM postgres:${POSTGRES_VERSION}

COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
COPY generate-tls.sh /usr/local/bin/generate-tls.sh
COPY docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/

RUN chmod +x /usr/local/bin/generate-tls.sh /docker-entrypoint-initdb.d/*.sh && \
    apk add --no-cache openssl

ENV PGDATA=/var/lib/postgresql/data

EXPOSE 5432
