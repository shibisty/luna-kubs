# Luna

This repository contains the authentication service, dashboard application, and infrastructure configuration for running them locally with Docker Compose and in Kubernetes.

## Project structure

- `luna-auth/` — Go-based authentication service
- `luna-dashboard/` — Nuxt dashboard application
- `postgres/` — PostgreSQL container configuration and initialization scripts
- `k8s/` — Kubernetes manifests for the services and PostgreSQL
- `docker-compose.yml` — local multi-container environment

## Components

### luna-auth

The auth service exposes REST endpoints for registration, login, and JWT verification. It connects to PostgreSQL and runs on port `8080` inside the container.

### postgres

A dedicated PostgreSQL container is used for the auth and dashboard databases and includes TLS setup and initialization scripts.

### luna-dashboard

The dashboard service is a Nuxt-based application that uses Prisma and a separate database connection.

## Run locally with Docker Compose

From the repository root:

```bash
docker compose up --build
```

Services:

- `luna-auth`: http://localhost:8080
- `luna-dashboard`: http://localhost:3000
- `postgres`: localhost:5432

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

Build the images for Minikube:

```bash
minikube image build -t luna-auth:latest ./luna-auth
minikube image build -t luna-dashboard:latest ./luna-dashboard
```

Apply the manifests:

```bash
kubectl apply -k k8s
```

Check the deployment:

```bash
kubectl get pods -n luna
kubectl get svc -n luna
```

Port-forward the services:

```bash
kubectl port-forward svc/luna-auth 8080:8080 -n luna
kubectl port-forward svc/luna-dashboard 3000:3000 -n luna
```

## Useful environment variables

### luna-auth

- `SECRET_KEY`
- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `DB_SSLMODE`
- `DB_SSLROOTCERT`

### luna-dashboard

- `DATABASE_URL`
- `PORT`

## Notes

- The Docker Compose configuration uses a shared network for the services.
- PostgreSQL initialization scripts create the required roles and databases on first startup.
- For production deployments, replace default secrets and passwords with secure values.
