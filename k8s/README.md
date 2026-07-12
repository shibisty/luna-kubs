Для работы по TLS необходимо:

1. Подготовить сертификаты PostgreSQL и CA.
2. Создать секрет `postgres-tls` с файлами `tls.crt`, `tls.key`, `ca.crt`.
3. Применить манифесты:
   kubectl apply -k ./k8s

При первом запуске PostgreSQL автоматически создаст:
- базу `auth_db`
- пользователя `auth_service`
- права доступа для этого пользователя

Для каждого нового микросервиса добавьте:
- отдельный Secret с `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- отдельный Deployment/Pod с нужными переменными окружения
- отдельный инициализационный скрипт в папке `postgres/docker-entrypoint-initdb.d`
