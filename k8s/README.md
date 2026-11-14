# Luna on Kubernetes

Kustomize, in three parts:

| Folder | |
| --- | --- |
| `base/` | what every cluster runs: postgres (StatefulSet), luna-dashboard, luna-auth, luna-pages and luna-files (migrations in an init container), NetworkPolicy, namespace `luna` |
| `local/` | minikube: images loaded from docker compose, nginx with a self-signed certificate |
| `do/` | DigitalOcean Kubernetes: images from DigitalOcean Container Registry, Let's Encrypt certificates (cert-manager), load balancers, mail and webmail |

| Workload | Image | Notes |
| --- | --- | --- |
| `postgres` (StatefulSet) | `luna-postgres:18` | TLS, creates `auth_db`, `dashboard`, `pages_db` and `files_db` on first start |
| `luna-dashboard` | `luna-dashboard` | init container `migrate`, then the server on 8080 |
| `luna-auth` | `luna-auth` | init container `migrate`, then the server on 8080 |
| `luna-pages` | `luna-pages` | init container `migrate`, then the server on 8080 |
| `luna-files` | `luna-files` | init container `migrate`, then the server on 8080; the bytes in Spaces (`do/`) or on a 2 GiB volume (`local/`, `FILES_STORAGE=disk`) |
| `luna-nginx` (LoadBalancer) | `luna-nginx` | 80 → 443; hides `/internal/` on every service host |
| `luna-mail` (StatefulSet, LoadBalancer) | `luna-mail` | `do/` only: postfix + dovecot, 25 / 587 / 993 |
| `roundcube` | `roundcube/roundcubemail` | `do/` only: webmail |

## minikube (`local/`)

On Windows (the Hyper-V driver) `luna.ps1` in the repository root does all of it:

```powershell
.\start.bat                 # or .\luna.ps1 start
.\stop.bat                  # minikube stop: the data stays
.\restart.bat               # stop + start
.\luna.ps1 restart auth     # one service: auth, dashboard, pages, files, nginx, postgres
.\luna.ps1 build dashboard  # rebuild images inside minikube and restart them (all without names)
.\luna.ps1 seed             # db:seed --only Platform in the dashboard
.\luna.ps1 status           # minikube, the pods, the health of every host
.\luna.ps1 logs files
```

`start` starts minikube. The first time, it also builds the images inside minikube and
generates `k8s/local/secrets.env` with luna-cli. Then it applies `k8s/local`, waits for the
services and points `auth.luna.local`, `dashboard.luna.local`, `pages.luna.local` and
`files.luna.local` at `minikube ip` in the hosts file. nginx listens on the VM's own ports 80
and 443 (`hostPort`), so you need no `minikube tunnel` and no `port-forward`. Hyper-V and the
hosts file need an administrator, so the script asks for one (UAC). The certificate is
self-signed.

Images are built inside minikube (`minikube docker-env`) rather than loaded with
`minikube image load`, because that command needs `wmic`, which current Windows no longer has.

By hand, anywhere else:

```sh
eval $(minikube docker-env) && docker compose build      # images inside minikube
cp k8s/local/secrets.env.example k8s/local/secrets.env   # fill in (luna-cli key:generate)
kubectl apply -k k8s/local
kubectl -n luna get pods -w
# hosts: the four *.luna.local names -> $(minikube ip)
```

## DigitalOcean (`do/`)

What you need: a DOKS cluster (two nodes of 2 GB or more), a Container
Registry, `doctl` and `kubectl` set up for both, and the domain's DNS hosted
at DigitalOcean (Networking → Domains): cert-manager proves the domain with
DNS-01 through the DigitalOcean API, the web and the mail host alike.

**1. Images.** Build, log in, push, connect the registry to the cluster:

```bat
docker compose build
doctl registry login
k8s\do\push.bat <registry> 0.1.0
doctl kubernetes cluster registry add <cluster>
```

Then in `k8s/do/kustomization.yaml` replace `luna-registry` with your
registry's name (in `images` and in the two `imagePullSecrets` patches: the
integration names the pull secret after the registry) and set the tags. A
new release: build, push a new tag, change the tags, apply.

**2. cert-manager**, once per cluster (check its site for a newer patch release):

```sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deployment --all --timeout=300s
```

**3. Settings and secrets** (all three files are git-ignored):

```sh
cp k8s/do/settings.env.example k8s/do/settings.env           # hosts, Let's Encrypt email
cp k8s/do/secrets.env.example  k8s/do/secrets.env            # passwords, service secrets
cp k8s/do/digitalocean.env.example k8s/do/digitalocean.env   # API token for DNS-01
cd luna-cli
go run . key:generate --env ../k8s/do/secrets.env --name AUTH_JWT_SECRET
go run . key:generate --env ../k8s/do/secrets.env --name LUNA_SERVICE_TOKEN
go run . key:generate --env ../k8s/do/secrets.env --name POSTGRES_PASSWORD
go run . key:generate --env ../k8s/do/secrets.env --name AUTH_DB_PASSWORD
go run . key:generate --env ../k8s/do/secrets.env --name DASHBOARD_DB_PASSWORD
go run . key:generate --env ../k8s/do/secrets.env --name PAGES_DB_PASSWORD
go run . key:generate --env ../k8s/do/secrets.env --name FILES_DB_PASSWORD
go run . key:generate --env ../k8s/do/secrets.env --name MAIL_PASSWORD
cd ..
```

luna-files keeps the bytes in a Spaces bucket: create it (with the CDN on) in
the same region, a Spaces access key, and put them into `settings.env`
(`FILES_S3_*`, `FILES_PUBLIC_URL` = the CDN endpoint) and `secrets.env`
(`FILES_S3_KEY`, `FILES_S3_SECRET`). Large uploads go from the browser
straight to the bucket, so its CORS settings must allow `PUT` and `GET` from
`https://<DASHBOARD_HOST>` (and from the clients' sites that upload) with the
headers `Content-Type` and `x-amz-acl`.

**4. Apply** and wait for the certificate (DNS-01 takes a few minutes; nginx
and mail start once it is there):

```sh
kubectl apply -k k8s/do
kubectl -n luna get certificate luna-tls -w
kubectl -n luna get svc luna-nginx luna-mail      # the two load balancers' addresses
```

**5. DNS.** `AUTH_HOST`, `DASHBOARD_HOST`, `PAGES_HOST`, `FILES_HOST`, `WEBMAIL_HOST` → A record to
`luna-nginx`'s address; `MAIL_HOST` → A record to `luna-mail`'s; an MX record
for `MAIL_DOMAIN` → `MAIL_HOST`; for delivery, SPF (`v=spf1 mx -all`) and
later DKIM/DMARC. Then uncomment `do-loadbalancer-hostname` in
`k8s/do/nginx.yaml` (see the comment there) and apply again.

**Check:** `cd luna-cli && go run . smoke --dashboard https://<DASHBOARD_HOST> --auth https://<AUTH_HOST>`
(no `--insecure`: the certificates are real).

### Notes

- **Outgoing mail.** DigitalOcean blocks outgoing SMTP (ports 25, 465 and
  587) on all Droplets, the cluster's nodes included. Until its support lifts
  the block for the account, mail arrives at `luna-mail` but nothing leaves
  it: luna-auth's password reset emails, replies from webmail. Ask in a
  support ticket, with the sending use case (transactional mail of the
  platform, low volume). The load balancer's address has no reverse DNS
  record of your choosing, which big mail providers weigh as well.
- **Certificates.** One certificate (`luna-tls`) for all five hosts, ECDSA,
  renewed by cert-manager 30 days before expiry. nginx reloads every 6
  hours and postfix/dovecot every 12, so a renewal is live within a day. To
  try the setup without Let's Encrypt's rate limits, point the Certificate's
  `issuerRef` at `letsencrypt-staging` first. If the DNS-01 check hangs, give
  cert-manager DigitalOcean's name servers:
  `--dns01-recursive-nameservers-only --dns01-recursive-nameservers=ns1.digitalocean.com:53`.
- **Client addresses.** The web load balancer speaks PROXY protocol to nginx,
  which passes the client address on as `X-Real-IP`; the services trust it
  from the cluster network (`HTTP_TRUSTED_PROXIES=private`, fullstack ≥ 0.1.1).
- **Data.** postgres (10 Gi), mail (5 Gi) and roundcube (1 Gi) live on
  DigitalOcean volumes (`do-block-storage`). Deleting the namespace keeps the
  volumes of the StatefulSets (`kubectl -n luna get pvc`). Backups are not
  set up yet.
- **Costs.** Two load balancers (web and mail) are billed apart from the
  nodes.
- `networkpolicy.yaml`: only nginx, luna-auth and luna-pages reach the
  dashboard, only nginx and the dashboard reach luna-auth and luna-pages,
  only the services reach postgres. DOKS enforces it (Cilium); minikube only with `--cni=calico`.
- The database passwords apply when the postgres volume is created. A
  service added later (luna-pages) gets its database on an existing volume
  with `kubectl -n luna exec postgres-0 -- bash /docker-entrypoint-initdb.d/10-luna.sh`
  (idempotent; push the new luna-postgres image and let the pod restart first). To start
  over locally: `kubectl delete -k k8s/local && kubectl -n luna delete pvc --all`.
