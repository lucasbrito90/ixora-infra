# Ixora — staging infrastructure (OpenTofu / Terraform)

Declarative **staging** footprint on **DigitalOcean** (Toronto `tor1` / App Platform `tor`):

| Component | Implementation |
|-----------|----------------|
| VPC | `digitalocean_vpc` |
| PostgreSQL | Managed cluster in VPC |
| Spaces | Private ACL bucket (optional via `manage_spaces_bucket`) |
| Laravel API | App Platform **service** `api` (web) + **worker** `queue` (`queue:work --queue=push,smart-home,default`, same image/env) |
| Nuxt Admin | App Platform **static site** (`npm run generate`) |
| Custom domains | Declared on App Platform apps; DNS steps documented |
| **Observability stack** | **Dedicated Droplet** — Grafana, Prometheus, Loki, Tempo, OTel Collector, Caddy reverse proxy |

> **Important:** The observability stack runs on a **Droplet**, not App Platform. Droplets do not receive `*.ondigitalocean.app` domains. DNS uses **A records** pointing to the Droplet public IPv4. See [`docs/operations/observability-dns-https.md`](../../docs/operations/observability-dns-https.md).

**No secrets belong in git.** Use `terraform.tfvars.example` as a template only; real values live in untracked `terraform.tfvars`, CI variables, or `TF_VAR_*`.

---

## Prerequisites

- DigitalOcean account with billing enabled.
- **API token** with write access (Apps, Databases, Networking, Spaces).
- **Spaces keys** (Spaces access key + secret) **only if** OpenTofu manages the bucket (`manage_spaces_bucket = true`). These are **separate** from `do_token` (S3-compatible API).
- GitHub repositories reachable by DigitalOcean App Platform (authorize the DO GitHub app / deploy keys as required in the DO UI).
- Laravel repo contains a **`Dockerfile`** suitable for App Platform (default path `Dockerfile`, port defaults to **8080** — override `api_http_port` / `api_dockerfile_path` if needed).
- Nuxt repo supports **`npm ci && npm run generate`** and writes static output to **`.output/public`**.

---

## Install OpenTofu

See [OpenTofu install docs](https://opentofu.org/docs/intro/install/). Terraform CLI (`terraform >= 1.6`) is largely compatible if you replace `tofu` with `terraform`.

---

## Configure credentials

```bash
export TF_VAR_do_token="dop_v1_..."           # or use terraform.tfvars (gitignored)
export TF_VAR_spaces_access_id="..."          # if managing Spaces bucket
export TF_VAR_spaces_secret_key="..."
```

OpenTofu does **not** read `DIGITALOCEAN_TOKEN` automatically for this stack — the provider uses `var.do_token`.

---

## Usage

```bash
cd opentofu/staging
cp terraform.tfvars.example terraform.tfvars   # edit locally; never commit
tofu init
tofu plan
tofu apply
```

### Lock file (`.terraform.lock.hcl`)

**Commit `.terraform.lock.hcl`** after `tofu init` so everyone uses the same provider versions. It is **not** ignored by `.gitignore`.

---

## Security notes

- Postgres sits in a **VPC**; runtime DB connections use **`private_host`** from the cluster.
- **`digitalocean_database_firewall`** allows **`digitalocean_vpc.staging.ip_range`** (private CIDR) plus optional extra `ip_addr` rules via `db_firewall_extra_ip_addrs` (default preserves existing ops/developer IP `108.180.255.58`). Apps must still use **`private_host`** for runtime; extra IPs are for direct psql/ops access only.
- Spaces bucket uses **`acl = "private"`**. Laravel still needs **runtime** Spaces keys (`DO_SPACES_*`) passed as App secrets — those are **not** stored in this repo.
- App env secrets use App Platform **SECRET** types where appropriate; OpenTofu may still show perpetual drift for encrypted values — see [provider discussion](https://github.com/digitalocean/terraform-provider-digitalocean/issues/869).

---

## Cost notes (indicative)

Staging is sized for **low cost**, not HA:

- Single-node Postgres (`db_node_size`, default `db-s-1vcpu-1gb`).
- API **web** + **`queue` worker** each use a **`basic-xxs`** component (worker has no public HTTP port).
- Static site pricing is modest vs always-on containers.

Check current DigitalOcean pricing pages — amounts change.

---

## What is **not** automated yet

- **GitHub ↔ DO** authorization (first deploy often needs UI confirmation).
- **DNS records** for API/admin at your registrar unless you uncomment/adapt examples in `domains.tf`.
- **Observability DNS**: set `observability_manage_dns = true` (DigitalOcean DNS) or create A records manually after `tofu apply` — see [`docs/operations/observability-dns-https.md`](../../docs/operations/observability-dns-https.md).
- **SSL** for App Platform custom domains: provisioned automatically after DNS validates.
- **Observability TLS**: Caddy obtains Let's Encrypt certificates automatically via TLS-ALPN-01 once DNS propagates.
- **Bucket CDN / CORS** toggles — only the private bucket + example CDN hostname output are scaffolded.
- **Migrations / APP_KEY rotation / Spaces key rotation** — operational tasks outside IaC.
- **Firewall**: DB trusted sources are the **staging VPC CIDR** (`ip_addr` rule) plus any **`db_firewall_extra_ip_addrs`** (default `108.180.255.58`). Adjust if you peer additional VPCs or need other ops IPs.

---

## Files

| File | Role |
|------|------|
| `providers.tf` | Provider pin + DO + Spaces credentials |
| `variables.tf` | Inputs (secrets as sensitive vars) |
| `main.tf` | Shared locals |
| `vpc.tf` | VPC |
| `database.tf` | Postgres + firewall |
| `spaces.tf` | Spaces bucket |
| `app-api.tf` | Laravel App Platform |
| `app-admin.tf` | Nuxt static site |
| `domains.tf` | DNS notes / optional patterns for App Platform |
| `observability.tf` | Observability Droplet, firewall, DNS records (Phase 8.8.5–8.8.6) |
| `outputs.tf` | Hostnames, IDs, DNS requirements, sensitive DB password |
| `templates/observability-cloud-init.yaml.tftpl` | Cloud-init: Docker, Caddy, systemd service |
| `terraform.tfvars.example` | Safe placeholders only |

---

## Assumptions & manual next steps

1. Confirm **`basic-xxs`** and **`db-s-1vcpu-1gb`** exist in Toronto; bump sizes if builds fail OOM.
2. Align **`api_http_port`** with your Dockerfile `EXPOSE`.
3. Set **all required secrets** (`APP_KEY`, discrete `api_firebase_*` credentials, mail, Laravel Spaces keys) via `TF_VAR_*` or untracked tfvars before first deploy - see `terraform.tfvars.example`.
4. Complete **custom domain DNS** using `tofu output api_live_url` / `admin_live_url` targets from DO.
5. **Bucket name** must be globally unique - adjust `spaces_bucket_name` if taken.
6. After apply, validate push readiness: [Push Notifications runtime validation](../../docs/architecture/backend/staging-digitalocean.md#push-notifications-runtime-validation) (`PUSH_PROVIDER=fcm`, named queue worker).

---

## Observability workflow

The observability stack requires three steps after `tofu apply`:

### Step 1: Validate cloud-init template

```bash
./scripts/validate-cloud-init.sh
```

Validates encoding, YAML syntax, and cloud-init schema before applying.

### Step 2: Repair or bootstrap the host

For a **new Droplet** (cloud-init already ran at creation - verify it completed):

```bash
ssh root@<droplet-ip>
cat /var/log/cloud-init-output.log | tail -20
```

For an **existing Droplet where cloud-init failed** (the current situation):

```bash
./scripts/repair-observability-host.sh --host 143.198.36.226 --user root
```

### Step 3: Bootstrap collector/.env

```bash
ssh root@143.198.36.226

export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"

cd /opt/ixora-observability
./scripts/bootstrap-collector-env.sh
```

### Step 4: Deploy the stack

From the operator machine:

```bash
./scripts/deploy-observability.sh --host 143.198.36.226 --user root
```

### Step 5: Verify

```bash
# Local (on Droplet)
curl -sf http://127.0.0.1:3000/api/health   # Grafana
curl -sf http://127.0.0.1:13133/health      # OTel Collector

# Public HTTPS
curl -I https://grafana-staging.ixora-app.app
curl -o /dev/null -w '%{http_code}\n' https://otel-staging.ixora-app.app/v1/traces
# Expect: Grafana -> 302, OTLP -> 401 (proves Caddy routing)
```

### OpenTofu plan target (emergency use only)

To plan/apply observability resources without touching the API (which has encrypted-env drift):

```bash
tofu plan \
  -target=digitalocean_droplet.observability \
  -target=digitalocean_firewall.observability
```

> **Warning:** Targeted apply is an emergency operational measure, not a normal workflow. All resources must be in sync before a full `tofu apply`.

---

## Known perpetual drift

`digitalocean_app.api` shows perpetual drift due to encrypted environment variables. This is a [known provider limitation](https://github.com/digitalocean/terraform-provider-digitalocean/issues/869) and does not affect the API runtime. Do not redeploy the API as part of observability fixes.
