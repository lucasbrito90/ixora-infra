# Observability DNS & HTTPS - Operations Guide

## Architecture overview

The Ixora observability stack runs on a **DigitalOcean Droplet** (not App Platform).

| Component | Runtime |
|-----------|---------|
| Grafana | Droplet - Docker container, port 3000 (127.0.0.1 only) |
| OpenTelemetry Collector | Droplet - Docker container, ports 4317/4318 (127.0.0.1 only) |
| Prometheus | Droplet - Docker container, port 9090 (127.0.0.1 only) |
| Loki | Droplet - Docker container, port 3100 (127.0.0.1 only) |
| Tempo | Droplet - Docker container, port 3200 (127.0.0.1 only) |
| Reverse proxy | Droplet - **Caddy**, port 443 (public) |

**Droplets do not receive automatic `*.ondigitalocean.app` domains.**
The `*.ondigitalocean.app` namespace belongs exclusively to DigitalOcean App Platform.
DNS for the observability Droplet must use **A records** pointing to the Droplet public IPv4.

### DNS provider

**DNS is managed externally via Cloudflare.** The `ixora-app.app` zone is authoritative at Cloudflare.
`observability_manage_dns = false` (the default). Records must be **DNS only** (grey cloud, no Cloudflare proxy).

> **Important:** Do NOT enable the Cloudflare proxy (orange cloud). Proxying intercepts TLS at Cloudflare's edge, preventing Caddy from completing the TLS-ALPN-01 ACME challenge against the Droplet IP.

### Public endpoints

| Endpoint | URL |
|----------|-----|
| Grafana dashboard | `https://grafana-staging.ixora-app.app` |
| OTLP HTTP ingest | `https://otel-staging.ixora-app.app` |

### Caddy reverse proxy

Caddy is installed by cloud-init and manages HTTPS automatically:

- Listens on **port 443** (public, firewall-allowed).
- Obtains and renews **Let's Encrypt certificates** without manual intervention.
- Routes `grafana-staging.ixora-app.app` -> `127.0.0.1:3000` (Grafana container).
- Routes `otel-staging.ixora-app.app` -> `127.0.0.1:4318` (Collector OTLP HTTP).
- **ACME challenge method:** TLS-ALPN-01 (no port 80 required).
- **Security:** Caddy blocks `/.env`, `/.git/*`, and other scan-target paths before proxying.

All internal ports (3000, 3100, 3200, 4317, 4318, 4319, 9090) are bound to `127.0.0.1` inside Docker and **blocked by the DigitalOcean Cloud Firewall**. Only ports 22 (SSH) and 443 (Caddy) are publicly reachable.

---

## Architecture separation

Host bootstrap and stack deployment are two distinct phases:

### Phase 1: Host bootstrap (cloud-init or repair script)

Runs once at Droplet creation (via cloud-init) or when repairing an existing host (via repair script).

Responsible for:
- Installing Docker and Docker Compose plugin
- Installing Caddy
- Creating `/etc/caddy/Caddyfile`
- Creating `/etc/systemd/system/ixora-observability.service`
- Creating `/usr/local/sbin/ixora-observability-preflight.sh`
- Creating deploy directories

> **Important:** `cloud-init` runs only during first Droplet creation. Updating the template does **not** repair an existing Droplet. Use `scripts/repair-observability-host.sh` to repair a running host.

### Phase 2: Stack deployment (deploy script)

Runs each time the stack needs to be deployed or updated.

Responsible for:
- Syncing `collector/` from the repository to the Droplet
- Running `docker compose pull` and `docker compose up -d`
- Verifying health endpoints
- Confirming port bindings and container status

> **Important:** Never run `docker compose down -v`. This destroys persistent data volumes.

---

## DNS configuration (Cloudflare)

DNS must be in place **before** Caddy can issue TLS certificates.

### Current Cloudflare DNS records

The following A records are configured in Cloudflare (`ixora-app.app` zone):

| Record type | Name | Value | Proxy status |
|------------|------|-------|--------------|
| A | `grafana-staging` | `143.198.36.226` | DNS only (grey cloud) |
| A | `otel-staging` | `143.198.36.226` | DNS only (grey cloud) |

### Adding or updating records in Cloudflare

1. Log in to Cloudflare -> select the `ixora-app.app` zone.
2. Go to **DNS -> Records -> Add record**.
3. Create/update record:
   - Type: `A`
   - Name: `grafana-staging` (or `otel-staging`)
   - IPv4 address: Droplet public IPv4 from `tofu output observability_public_ipv4`
   - TTL: `Auto` or `300`
   - Proxy status: **DNS only** (grey cloud)

### Retrieving the required values from OpenTofu

```bash
cd opentofu/staging
tofu output observability_public_ipv4
tofu output observability_dns_requirements
```

---

## Cloud-init notes

The cloud-init template is located at:

```
opentofu/staging/templates/observability-cloud-init.yaml.tftpl
```

### Known history

A previous version of the template contained Unicode em dashes (`--` encoded as `\xE2\x80\x94`) which caused cloud-init to fail with:

```
Failed loading yaml blob
unacceptable character #x0080
Failed at merging in cloud config part
```

The template is now **pure ASCII**. The validation script at `scripts/validate-cloud-init.sh` checks this automatically.

### Validating the template

```bash
./scripts/validate-cloud-init.sh
```

This renders the template with test values and validates:
- UTF-8 / ASCII encoding
- No BOM
- First line is `#cloud-config`
- No corrupted characters
- YAML syntax (via PyYAML)
- cloud-init schema (if available locally)

### Cloud-init runs only at first creation

After a Droplet is created, cloud-init does **not** re-run even if `user_data` changes in OpenTofu. The `observability.tf` lifecycle block ignores `user_data` changes to prevent accidental Droplet replacement.

To repair an existing host without recreating it, use:

```bash
./scripts/repair-observability-host.sh --host <droplet-ip> --user root
```

---

## How automatic TLS works

Caddy uses the [ACME TLS-ALPN-01 challenge](https://letsencrypt.org/docs/challenge-types/#tls-alpn-01):

1. Caddy starts and reads the `Caddyfile` for the configured hostnames.
2. Caddy connects to Let's Encrypt and requests a certificate for each hostname.
3. Let's Encrypt sends a TLS handshake to the Droplet on port 443.
4. Caddy responds with a special TLS certificate proving domain control.
5. Let's Encrypt issues the certificate; Caddy stores it automatically.
6. Caddy renews certificates before expiry (typically ~30 days before).

**Port 80 is not required** - TLS-ALPN-01 uses port 443 exclusively.
Port 80 is not open in the DigitalOcean Cloud Firewall and should remain closed.

---

## How to repair the existing Droplet

Run from the operator machine (requires SSH access to the Droplet):

```bash
./scripts/repair-observability-host.sh \
  --host 143.198.36.226 \
  --user root
```

This script is **idempotent** - safe to run multiple times. It will:
- Check SSH connectivity
- Install Docker if absent
- Install Caddy if absent
- Create/update `/etc/caddy/Caddyfile` with path hardening
- Validate Caddy configuration
- Reload Caddy
- Create `/opt/ixora-observability` directory
- Install/update systemd unit and preflight script

---

## How to bootstrap the remote .env

SSH to the Droplet (after the collector/ directory is present from `deploy-observability.sh`):

```bash
ssh root@143.198.36.226

# On the Droplet:
cd /opt/ixora-observability

export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"

./scripts/bootstrap-collector-env.sh
```

The script creates `collector/.env` with mode `0600` from `collector/.env.example`.
Secrets are never printed or logged.

---

## How to deploy the stack (first deployment)

Follow this exact five-step order. The order matters: **files must be synced before `bootstrap-collector-env.sh` can run**, because the bootstrap script requires `collector/.env.example` to be present on the host.

### Step 1: Validate source

```bash
./scripts/validate-cloud-init.sh
```

### Step 2: Repair or bootstrap the host

For an **existing Droplet where cloud-init failed**:

```bash
./scripts/repair-observability-host.sh --host 143.198.36.226 --user root
```

For a **newly created Droplet** (cloud-init ran at creation): cloud-init bootstraps the host automatically.

### Step 3: Synchronize repository files (no containers started)

```bash
./scripts/deploy-observability.sh \
  --host 143.198.36.226 \
  --user root \
  --sync-only
```

Copies `collector/` and `scripts/` to the Droplet. Does not start containers. Does not require `collector/.env` to exist yet. The script prints the exact next command to run after it completes.

Dry-run preview:

```bash
./scripts/deploy-observability.sh \
  --host 143.198.36.226 \
  --user root \
  --sync-only \
  --dry-run
```

### Step 4: Create collector/.env on the remote host

Only run **after Step 3** has synced the files:

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability

export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"

./scripts/bootstrap-collector-env.sh
exit
```

The script creates `collector/.env` with mode `0600` from `collector/.env.example`. Secrets are never printed or logged.

### Step 5: Run the full deployment

```bash
./scripts/deploy-observability.sh --host 143.198.36.226 --user root
```

This will:
1. Verify SSH connectivity, Docker, and Caddy presence
2. rsync `collector/` and `scripts/` to the Droplet (never copies `.env`, `.git`, state files)
3. SSH in and run `docker compose pull` + `docker compose up -d`
4. Wait for all mandatory health endpoints (Collector, Prometheus, Loki, Tempo, Grafana)
5. Verify container status and port bindings
6. Exit non-zero if any mandatory service is unhealthy

### Subsequent updates

For stack updates after the initial deployment (`.env` already exists):

```bash
./scripts/deploy-observability.sh --host 143.198.36.226 --user root
```

### Dry run (preview only)

```bash
./scripts/deploy-observability.sh --host 143.198.36.226 --user root --dry-run
```

### On the Droplet directly (if already SSHed in)

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability
./scripts/deploy-observability.sh
```

---

## How to verify Caddy

```bash
ssh root@143.198.36.226

# Service status
systemctl status caddy --no-pager

# Validate configuration
caddy validate --config /etc/caddy/Caddyfile

# Check port 443
ss -lntp | grep ':443'

# Check TLS certificate logs
journalctl -u caddy -n 50 --no-pager | grep -i "certificate\|acme\|tls\|error"
```

---

## How to verify Docker Compose

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability/collector

# Validate compose file
docker compose config

# Show container status
docker compose ps

# Show recent logs
docker compose logs --tail=100

# Per-service logs
docker compose logs --tail=100 collector
docker compose logs --tail=100 grafana
docker compose logs --tail=100 prometheus
docker compose logs --tail=100 loki
docker compose logs --tail=100 tempo
```

---

## How to verify local services

```bash
ssh root@143.198.36.226

# Health endpoints (from host)
curl -sf http://127.0.0.1:13133/health   # OTel Collector health_check extension
curl -sf http://127.0.0.1:9090/-/ready   # Prometheus
curl -sf http://127.0.0.1:3100/ready     # Loki
curl -sf http://127.0.0.1:3200/ready     # Tempo
curl -sf http://127.0.0.1:3000/api/health # Grafana

# Verify internal ports are 127.0.0.1 only (not publicly exposed)
ss -lntp | grep -E ':(3000|4317|4318|4319|9090|3100|3200) '
# All should show 127.0.0.1:<port>, never 0.0.0.0:<port>
```

---

## How to verify public HTTPS

From an external machine (not the Droplet):

```bash
# Grafana - expect HTTP 200 or 302 (login redirect)
curl -I https://grafana-staging.ixora-app.app

# OTLP - expect HTTP 401 or 405 (auth required = Caddy routing works, not 502)
curl -o /dev/null -w '%{http_code}\n' https://otel-staging.ixora-app.app/v1/traces

# Verify TLS certificate
openssl s_client -connect grafana-staging.ixora-app.app:443 -servername grafana-staging.ixora-app.app </dev/null 2>/dev/null | openssl x509 -noout -dates
```

---

## How to roll back the stack without deleting volumes

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability/collector

# Stop services (preserves volumes)
docker compose stop

# Restore previous image versions in .env
# (update GRAFANA_VERSION, PROMETHEUS_VERSION, etc.)
nano /opt/ixora-observability/collector/.env

# Restart with previous images
docker compose pull
docker compose up -d
```

> **Never run:** `docker compose down -v` - this destroys all persistent data volumes.

---

## How to rotate credentials

### Grafana admin password

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability/collector

# Edit .env - update GF_ADMIN_PASSWORD
# (generate: openssl rand -base64 24)
nano .env

# Restart Grafana
docker compose restart grafana
```

### Collector bearer token (OTEL_INGEST_API_KEY_*)

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability/collector

# Edit .env - update OTEL_INGEST_API_KEY_BACKEND and/or OTEL_INGEST_API_KEY_MOBILE
nano .env

# Restart Collector
docker compose restart collector
```

Then update the corresponding secrets in all clients (App Platform env vars, mobile build config).

---

## How to inspect logs

```bash
ssh root@143.198.36.226
cd /opt/ixora-observability/collector

# All services
docker compose logs --tail=200

# Service-specific
docker compose logs --tail=200 collector
docker compose logs --tail=200 grafana
docker compose logs --tail=200 prometheus

# Caddy (reverse proxy)
journalctl -u caddy -n 100 --no-pager

# Systemd unit
journalctl -u ixora-observability -n 50 --no-pager
```

---

## How to perform a Droplet rebuild

For a detailed, safe rebuild procedure using OpenTofu-controlled replacement, see:

```
docs/operations/observability-droplet-rebuild.md
```

**Key points:**

- `prevent_destroy = true` is set in `observability.tf` and must be temporarily removed only on a dedicated maintenance branch, then immediately restored after replacement.
- A Reserved IP (`observability_use_reserved_ip = true`) prevents DNS changes during rebuild; without it, both `grafana-staging` and `otel-staging` A records must be updated in Cloudflare after the new Droplet is created.
- Post-rebuild deployment follows the same five-step order as a first deployment (see above).
- **Never delete the Droplet manually from the DigitalOcean console** — use `tofu plan -replace` so the replacement is recorded in state.

---

## DNS propagation

TTL 300 means resolvers cache records for 5 minutes. After creating the A records:

- Wait **5-10 minutes** for propagation before Caddy can issue a certificate.
- Caddy will retry certificate issuance automatically - no manual action needed.
- Certificate issuance typically completes within **1-2 minutes** of DNS propagation.

---

## Verification commands

### 1. Check OpenTofu outputs

```bash
cd opentofu/staging
tofu output observability_public_ipv4
tofu output observability_grafana_url
tofu output observability_otlp_http_url
tofu output observability_dns_requirements
```

### 2. Verify DNS propagation

```bash
dig +short grafana-staging.ixora-app.app
dig +short otel-staging.ixora-app.app
```

Both should return the Droplet public IPv4 from `tofu output observability_public_ipv4`.

### 3. Test Grafana HTTPS

```bash
curl -I https://grafana-staging.ixora-app.app
```

Expected: `HTTP/2 302` (redirect to Grafana login) or `HTTP/2 200`.

### 4. Test OTLP HTTP endpoint

```bash
curl -o /dev/null -w '%{http_code}\n' https://otel-staging.ixora-app.app/v1/traces
```

Expected: `401` (bearer token required) or `405`. **Either proves DNS, TLS, and Caddy routing work.** A `502` means the Collector is not running.

### 5. Verify certificates on the Droplet

```bash
ssh root@$(tofu output -raw observability_public_ipv4)
journalctl -u caddy --since="1 hour ago" | grep -i "certificate\|acme\|tls"
```

---

## Rollback procedure

If you need to remove the managed DNS records (when using DigitalOcean DNS):

```bash
cd opentofu/staging
# Edit terraform.tfvars: set observability_manage_dns = false
tofu plan   # confirm only digitalocean_record resources are removed
tofu apply
```

The Droplet, firewall, and all observability services remain unaffected.
Manual Cloudflare DNS records must be removed separately in the Cloudflare dashboard.

---

## Reserved IP (optional)

When `observability_use_reserved_ip = true`, OpenTofu allocates a DigitalOcean Reserved IP and assigns it to the Droplet. DNS records point to the Reserved IP instead of the ephemeral Droplet IP.

This provides **DNS stability**: if the Droplet is ever replaced, the Reserved IP can be reassigned to the new Droplet without updating DNS records.

```hcl
observability_use_reserved_ip = true
```

Check `tofu output observability_public_ipv4` - it will show the Reserved IP when enabled.
Check `tofu output observability_reserved_ip_enabled` to confirm the feature is active.

---

## OpenTofu variables reference

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `observability_grafana_hostname` | string | `grafana-staging.ixora-app.app` | FQDN for the Grafana endpoint |
| `observability_otel_hostname` | string | `otel-staging.ixora-app.app` | FQDN for the OTLP HTTP endpoint |
| `observability_manage_dns` | bool | `false` | Create A records in DigitalOcean DNS |
| `observability_dns_zone_name` | string | `null` | DO DNS zone (e.g. `ixora-app.app`) |
| `observability_dns_ttl` | number | `300` | TTL for managed DNS records (seconds) |
| `observability_use_reserved_ip` | bool | `false` | Allocate a Reserved IP for DNS stability |
| `observability_https_allowed_cidrs` | list(string) | `["0.0.0.0/0", "::/0"]` | CIDRs allowed to reach port 443 |
| `observability_ssh_allowed_cidrs` | list(string) | `[]` | CIDRs allowed SSH (port 22) |

---

## Security findings

The following sensitive paths were scanned externally. Caddy now returns 404 for:

- `/.env`
- `/.env.*`
- `/.git` and `/.git/*`
- `/config.json`
- `/wp-admin/*`, `/wp-login.php`

OTLP endpoint (`otel-staging.ixora-app.app`) only accepts requests to:

- `/v1/traces`
- `/v1/metrics`
- `/v1/logs`

All other paths return 404 before reaching the Collector.

---

## Constraints

- Do **not** create `digitalocean_app` resources for the observability stack - it runs on a Droplet.
- Do **not** use `*.ondigitalocean.app` URLs - those belong to App Platform only.
- Do **not** expose ports 3000, 3100, 3200, 4317, 4318, 4319, or 9090 directly to the internet.
- Do **not** open port 80 - the TLS-ALPN-01 challenge requires only port 443.
- OTLP gRPC (port 4317) is not exposed publicly - applications use OTLP HTTP over HTTPS.
- Do **not** enable Cloudflare proxy (orange cloud) - use DNS only (grey cloud).
