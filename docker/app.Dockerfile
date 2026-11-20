# syntax=docker/dockerfile:1.7
#
# One image recipe for every Go service of the workspace:
#
#   docker build -f docker/app.Dockerfile --build-arg SERVICE=luna-auth \
#     --secret id=github_token,env=GITHUB_TOKEN -t luna-auth:local .
#
# The context is the repository root, because a service builds against its
# workspace siblings (luna-keys). gtr resolves the dependencies from gtr.lock
# (`gtr ci`, frozen). The package store is a BuildKit cache mount, so a
# rebuild first tries the store alone (`--offline`, no network); only when
# something is missing does gtr read tags and download packages through the
# GitHub API. Pass a token as the github_token secret to get past the 60
# requests an hour of anonymous access; it never lands in a layer. The store
# is locked while gtr runs, so parallel builds fill it once and share it.

ARG GO_VERSION=1.26

# --- gtr itself ---------------------------------------------------------------
FROM golang:${GO_VERSION}-alpine AS gtr
RUN apk add --no-cache git
ARG GTR_REPO=https://github.com/shibisty/gtr-manager.git
ARG GTR_REF=master
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    git clone --depth 1 --branch "${GTR_REF}" "${GTR_REPO}" /src/gtr \
 && cd /src/gtr \
 && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /usr/local/bin/gtr ./cmd/gtr-manager

# --- the service ----------------------------------------------------------------
FROM golang:${GO_VERSION}-alpine AS build
RUN apk add --no-cache git ca-certificates
COPY --from=gtr /usr/local/bin/gtr /usr/local/bin/gtr
WORKDIR /luna
COPY gtr.json gtr.lock ./
COPY luna-keys/ luna-keys/
COPY luna-cli/ luna-cli/
COPY luna-dashboard/ luna-dashboard/
COPY luna-auth/ luna-auth/
COPY luna-pages/ luna-pages/
COPY luna-files/ luna-files/
COPY luna-forms/ luna-forms/
ARG SERVICE
ARG TARGETOS=linux
ARG TARGETARCH=amd64
RUN test -n "${SERVICE}" || { echo "--build-arg SERVICE=<workspace member> is required" >&2; exit 1; }
RUN --mount=type=cache,target=/root/.gtr,sharing=locked \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=secret,id=github_token \
    export GITHUB_TOKEN="$(cat /run/secrets/github_token 2>/dev/null || true)" \
 && { gtr ci --offline 2>/dev/null || gtr ci; } \
 && cd "${SERVICE}" \
 && gtr build --target "${TARGETOS}/${TARGETARCH}" --out /out \
 && find /out -type f -name "${SERVICE}" -exec cp {} /app \; \
 && test -x /app

# --- runtime: static binary, no shell, non-root ----------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /app /app
ENV APP_ENV=production \
    HTTP_ADDR=:8080
EXPOSE 8080
USER nonroot:nonroot
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
