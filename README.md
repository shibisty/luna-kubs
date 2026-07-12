# Luna

This repository contains the authentication service and infrastructure configuration for running it locally with Docker Compose and in Kubernetes.

## Project structure

- `auth/` — Go-based authentication service
- `dashboard/` — Nuxt dashboard application
- `postgres/` — PostgreSQL container configuration and initialization scripts
- `docker-compose.yml` — local multi-container environment
- `kubernetes.yml` — Kubernetes manifests for auth and PostgreSQL
- `k8s/` — additional Kubernetes resources if present

## Components

### Auth service

The auth service exposes REST endpoints for registration, login, and JWT verification. It connects to PostgreSQL and runs on port `8080` inside the container, exposed as `8000` locally.

### PostgreSQL

A dedicated PostgreSQL container is used for the auth database and also supports the dashboard service.

### Dashboard

The dashboard service is a Nuxt-based application that uses Prisma and a separate database connection.

## Run locally with Docker Compose

From the repository root:

```bash
docker compose up --build
```

Services:

- Auth: `http://localhost:8000`
- Dashboard: `http://localhost:3000`
- PostgreSQL: `localhost:5432`

Stop the stack:

```bash
docker compose down
```

Remove volumes as well:

```bash
docker compose down -v
```

## Run in Kubernetes

Start Minikube:

```bash
minikube start
```

Build the auth image for Minikube:

```bash
minikube image build -t auth:latest ./auth
```

Apply the manifests:

```bash
kubectl apply -f kubernetes.yml
```

Check the deployment:

```bash
kubectl get pods -n auth
kubectl get svc -n auth
```

Port-forward the service:

```bash
kubectl port-forward svc/auth 8000:80 -n auth
```

## Useful environment variables

### Auth service

- `SECRET_KEY`
- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `DB_SSLMODE`

### Dashboard service

- `DATABASE_URL`
- `PORT`

## Notes

- The Docker Compose configuration uses a shared network for the services.
- PostgreSQL initialization scripts create the required roles and databases on first startup.
- For production deployments, replace default secrets and passwords with secure values.
