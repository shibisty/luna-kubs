#!/bin/bash
set -euo pipefail

CERT_DIR="/var/lib/postgresql/tls"
mkdir -p "$CERT_DIR"

if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ] || [ ! -f "$CERT_DIR/ca.crt" ]; then
  echo "Generating PostgreSQL TLS certificates..."

  openssl req -new -x509 -days 3650 -nodes \
    -subj "/CN=postgres" \
    -out "$CERT_DIR/ca.crt" \
    -keyout "$CERT_DIR/ca.key"

  openssl req -newkey rsa:2048 -nodes \
    -subj "/CN=postgres" \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.csr"

  openssl x509 -req -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/server.crt" \
    -days 3650 \
    -sha256

  rm -f "$CERT_DIR/server.csr"
fi

chown -R postgres:postgres "$CERT_DIR"
chmod 700 "$CERT_DIR"
chmod 600 "$CERT_DIR/server.key" "$CERT_DIR/ca.key"
chmod 644 "$CERT_DIR/server.crt" "$CERT_DIR/ca.crt"
