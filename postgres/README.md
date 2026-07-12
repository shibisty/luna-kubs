Для PostgreSQL с TLS:

1. Сборка образа:
   docker build -t luna-postgres ./postgres

2. Запуск:
   docker run --rm -p 5432:5432 luna-postgres

3. При первом старте будут автоматически сгенерированы:
   - /var/lib/postgresql/tls/server.crt
   - /var/lib/postgresql/tls/server.key
   - /var/lib/postgresql/tls/ca.crt

4. Для Kubernetes нужно положить эти файлы в Secret `postgres-tls`.
