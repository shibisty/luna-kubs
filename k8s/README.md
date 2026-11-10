# Luna on Kubernetes

Manifests for a local cluster (minikube). They run the same images that
`docker compose build` makes, in the namespace `luna`:

| Workload | Image | Notes |
| --- | --- | --- |
| `postgres` (StatefulSet) | `luna-postgres:18` | TLS, creates `auth_db` and `dashboard` on first start |
| `luna-dashboard` | `luna-dashboard:local` | init container `migrate`, then the server on 8080 |
| `luna-auth` | `luna-auth:local` | init container `migrate`, then the server on 8080 |
| `luna-nginx` (LoadBalancer) | `luna-nginx:local` | 80 → 443, self-signed certificate, hides the dashboard's `/internal/` |

## Run

```sh
# 1. Images (from the repository root)
docker compose build
minikube image load luna-postgres:18 luna-dashboard:local luna-auth:local luna-nginx:local

# 2. Secrets: copy and fill in (generate the two service secrets with luna-cli)
cp k8s/secrets.env.example k8s/secrets.env
cd luna-cli
go run . key:generate --env ../k8s/secrets.env --name AUTH_JWT_SECRET
go run . key:generate --env ../k8s/secrets.env --name LUNA_SERVICE_TOKEN
cd ..

# 3. Apply, then give the LoadBalancer an address
kubectl apply -k k8s
kubectl -n luna get pods -w
minikube tunnel
```

Point `auth.luna.local` and `dashboard.luna.local` at the tunnel address in
your hosts file. The certificate is self-signed.

## Notes

- Configuration that is not secret is the `luna-config` ConfigMap in
  `kustomization.yaml`; secrets are `luna-secrets`, generated from
  `secrets.env`. Both get a content hash in their names, so changing them
  rolls the Deployments.
- `nginx/*.conf` here mirror `../nginx/sites/` (kustomize only reads files
  below this folder); change both.
- `networkpolicy.yaml` lets only luna-auth and nginx reach the dashboard and
  only the two services reach postgres. minikube enforces it only with a
  policy-aware CNI: `minikube start --cni=calico`.
- The database passwords apply when the postgres volume is created. To start
  over: `kubectl delete -k k8s && kubectl -n luna delete pvc --all`.
