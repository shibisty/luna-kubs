# Luna

A backend platform for client applications. A developer registers an
application in the dashboard and gets API keys with scopes; the
application then uses Luna's services with those keys.

| Service | What it does |
| --- | --- |
| [luna-dashboard](luna-dashboard) | The developer console: accounts, applications, API keys, and each application's users and their data. The only key authority; luna-auth asks it about every key (internal API, cached). |
| [luna-auth](luna-auth) | Registration and sign-in of the application's own end users (username or email + password), JWTs per application, rotating refresh tokens, password reset, user administration, and the application's own data about each user (text values by key). |
| [luna-pages](luna-pages) | A small CMS per application: a site, layouts, templates with typed fields, and pages (free ones built in GrapesJS, or entries that fill a template); drafts behind an editor API, published and rendered as sanitized HTML. |
| [luna-files](luna-files) | A small drive per application: folders and files in DigitalOcean Spaces, uploads through the API or presigned straight to Spaces, public CDN links and signed links for private files, a quota per application. |

Shared code and tools:

| Package | |
| --- | --- |
| [luna-keys](luna-keys) | Key format, scopes, the introspection client and handler, `RequireKey` and CORS middleware. Standard library only. |
| [luna-cli](luna-cli) | `key:generate` for secrets, `smoke` for an end-to-end check of the running stack. |

Everything is Go on [fullstack.go](https://github.com/shibisty/fullstack.go)
and managed by [gtr](https://github.com/shibisty/gtr-manager) as one
workspace: `gtr.json` lists the members, `gtr.lock` pins every dependency,
and each member's `go.mod` is generated (git-ignored).

## Keys and scopes

| Scope | Allows |
| --- | --- |
| `auth:login` | register, sign in, refresh, sign out, `/v1/me` and `/v1/me/data` (read-only), password reset |
| `auth:users.read` | list and read the application's users |
| `auth:users.write` | change and delete them |
| `auth:data.read` | read the application's data about its users |
| `auth:data.write` | set and delete that data |
| `pages:read` | read published pages (browser keys too) |
| `pages:write` | edit and publish pages |
| `files:read` | list and read files (browser keys: public files only) |
| `files:write` | upload, change and delete files |

Keys go in the `X-API-Key` header. A server key (`sk_live_…`) is for
backends and is refused when a browser sends it; a browser key (`pk_live_…`)
works only from the application's allowed origins and only with
`auth:login`, `pages:read` and `files:read`. The dashboard stores only a key's SHA-256.

## Layout

```
luna-dashboard/  luna-auth/  luna-pages/  luna-files/  luna-keys/  luna-cli/   the workspace (submodules)
docker/app.Dockerfile      one image recipe for every service
docker-compose.yml         the local stack
nginx/                     the edge: TLS, the service hosts
postgres/                  PostgreSQL 18 with TLS and the service databases
k8s/                       the same stack on Kubernetes: base/, local/ (minikube), do/ (DigitalOcean)
mail/  roundcube/  certbot/   local mail, webmail, certificates
```

## Run it

You need Docker, Go 1.26 and gtr. Point the hosts at your machine
(`C:\Windows\System32\drivers\etc\hosts` or `/etc/hosts`):

```
127.0.0.1 dashboard.luna.local auth.luna.local pages.luna.local files.luna.local mail.luna.local
```

### The whole stack in Docker

```bash
git clone --recurse-submodules https://github.com/shibisty/luna-kubs.git luna
cd luna
cp .env.example .env
gtr install                                  # the workspace, for luna-cli
cd luna-cli
go run . key:generate --env ../.env --name AUTH_JWT_SECRET
go run . key:generate --env ../.env --name LUNA_SERVICE_TOKEN
cd ..
# set GITHUB_TOKEN in .env: gtr fetches packages through the GitHub API while building
docker compose build
docker compose up -d
```

- https://dashboard.luna.local — the console (sign up, create an application and a key)
- https://auth.luna.local/docs — luna-auth's API (Swagger UI); `/openapi.yaml` is the document
- https://pages.luna.local/docs — luna-pages' editor API (a key with `pages:write`)
- https://files.luna.local/docs — luna-files' API (a key with `files:read` / `files:write`); locally the
  files are kept in the `files-data` volume and served at `/blobs/` (set `FILES_STORAGE=s3` and the
  `FILES_S3_*` variables in `.env` to use Spaces)

The certificate is self-signed. `postgres-init` creates any missing service
database (also on an existing volume), then migrations run before each
service starts (`luna-*-migrate`). Check the stack end to end:

```bash
cd luna-cli && go run . smoke --insecure
```

With `APP_ENV=local` (the default in `.env.example`) password reset links
go to luna-auth's log (`docker compose logs luna-auth`) instead of email.

### A service from source

Postgres from compose listens on `127.0.0.1:5433` (TLS, `sslmode=require`).

```bash
docker compose up -d postgres
gtr install
cd luna-dashboard && cp .env.example .env    # then the secrets, see the file
gtr dev                                      # rebuilds and restarts on change
```

The same for luna-auth, luna-pages and luna-files, whose `LUNA_DASHBOARD_TOKEN` must be one of the
dashboard's `LUNA_SERVICE_TOKENS`. Each service's README has the rest.

### Kubernetes

[k8s/README.md](k8s/README.md): `k8s/local` runs the compose images on
minikube; `k8s/do` deploys to DigitalOcean Kubernetes with images from its
Container Registry, Let's Encrypt certificates through cert-manager (DNS-01),
load balancers for the web and for mail, and webmail. DigitalOcean blocks
outgoing SMTP from its machines until its support lifts the block.

## Tests

```bash
gtr run -r test                 # every member
```

The database tests run when `TEST_DATABASE_DSN` points at an empty test
database, one per service (they are skipped otherwise).

API collections for Postman (and newman) are in each service's `docs/postman/`.

## License

MIT
