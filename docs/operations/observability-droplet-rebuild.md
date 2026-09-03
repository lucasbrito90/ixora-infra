# Observability Droplet Rebuild Procedure

> **This procedure has not been executed. It is documented here for operator reference.**
> Do not run it without explicitly reviewing the current state of the infrastructure.

---

## When to use this procedure

Use a controlled rebuild when:

- The existing Droplet cannot be repaired with `scripts/repair-observability-host.sh`.
- The Droplet was bootstrapped from a broken `cloud-init` document and no valid observability data exists to preserve.
- A clean host is required to validate a corrected `cloud-init` template.

**Do not** delete the Droplet manually from the DigitalOcean console. OpenTofu must manage the replacement so the state file remains accurate.

---

## Current state assessment

### Resource address

```
digitalocean_droplet.observability[0]
```

Defined in `opentofu/staging/observability.tf`.

### `prevent_destroy` behavior

`prevent_destroy = true` is set in the lifecycle block. This means `tofu apply` and `tofu plan -replace` will refuse to proceed without first removing the guard. The constraint is intentional — it prevents accidental Droplet deletion during routine `tofu apply` runs.

### `ignore_changes` behavior for `user_data`

`ignore_changes = [user_data]` is set. Updating the cloud-init template in the repository does **not** trigger a Droplet replacement on `tofu apply`. The corrected template will only be applied to a new Droplet created by a deliberate `-replace` operation.

### Reserved IP

`observability_use_reserved_ip` defaults to `false`. When not enabled, the observability Droplet uses an ephemeral IPv4 address. If the Droplet is replaced, the new Droplet will receive a **different public IPv4**, requiring Cloudflare DNS record updates.

**Recommendation:** Enable `observability_use_reserved_ip = true` before rebuilding. This can be applied independently (without replacing the Droplet) and allocates a Reserved IP that survives Droplet replacement. See [Safe Reserved IP apply](#safe-reserved-ip-apply-before-rebuild).

### Block volume

`observability_use_block_volume` defaults to `false`. No block volume is currently attached. All Docker container data (Prometheus, Loki, Tempo, Grafana) lives on the Droplet root disk.

### Data that would be lost

| Data | Location | Preserved after rebuild? |
|------|----------|--------------------------|
| Grafana dashboards, users, alerts | Docker volume `grafana_data` (root disk) | **No** |
| Prometheus metrics history | Docker volume `prometheus_data` (root disk) | **No** |
| Loki log data | Docker volume `loki_data` (root disk) | **No** |
| Tempo trace data | Docker volume `tempo_data` (root disk) | **No** |
| `collector/.env` | `/opt/ixora-observability/collector/.env` (root disk) | **No** — must be re-created |
| Caddy TLS certificates | `/var/lib/caddy` (root disk) | **No** — re-issued automatically |

**Current state assessment:** The observability Docker stack has never been successfully deployed. No persistent data was written to the volumes. Data loss is acceptable.

### Public IP behavior

| Scenario | IP behavior | DNS action required |
|----------|------------|---------------------|
| No Reserved IP (`use_reserved_ip = false`) | New Droplet gets a new ephemeral IPv4 | Update `grafana-staging` and `otel-staging` A records in Cloudflare |
| Reserved IP enabled (`use_reserved_ip = true`) | Reserved IP is reassigned to new Droplet | No DNS change required |

### Firewall behavior

`digitalocean_firewall.observability` is attached via `droplet_ids = [digitalocean_droplet.observability[0].id]`. When the Droplet is replaced, OpenTofu will update the firewall attachment automatically as part of the same apply. No manual firewall reassignment is needed.

### Cloudflare DNS

The `ixora-app.app` zone is managed externally at Cloudflare. `observability_manage_dns = false` (default). DNS records must be updated manually in the Cloudflare dashboard after a rebuild if no Reserved IP is in use.

Both records must remain **DNS only** (grey cloud). Do not enable the Cloudflare proxy — it would break Caddy's TLS-ALPN-01 ACME challenge.

---

## Pre-rebuild checklist

Before proceeding:

- [ ] Confirm there is no observability data to preserve (no successful deployment has run).
- [ ] Back up any useful configuration from the existing host:
  ```bash
  # Back up Caddyfile (no secrets)
  ssh root@143.198.36.226 'cat /etc/caddy/Caddyfile' > /tmp/backup-Caddyfile.txt

  # Check for any custom files in deploy path (there should be none worth keeping)
  ssh root@143.198.36.226 'ls -la /opt/ixora-observability/collector/ 2>/dev/null || echo "empty"'
  ```
- [ ] Validate the corrected cloud-init template:
  ```bash
  ./scripts/validate-cloud-init.sh
  ```
- [ ] Run OpenTofu fmt and validate:
  ```bash
  cd opentofu/staging
  tofu fmt -recursive .
  tofu validate
  ```
- [ ] Consider enabling Reserved IP first (see below).
- [ ] Confirm Cloudflare DNS records are DNS-only (grey cloud).

---

## Safe Reserved IP apply before rebuild

If `observability_use_reserved_ip` is currently `false`, you can enable it and apply it **without replacing the Droplet** in a separate step before the rebuild. This gives DNS stability during and after the rebuild.

```bash
# In terraform.tfvars (gitignored):
observability_use_reserved_ip = true
```

```bash
cd opentofu/staging

# Plan - should show only Reserved IP resource creation, no Droplet replacement
tofu plan \
  -target='digitalocean_reserved_ip.observability[0]' \
  -target='digitalocean_reserved_ip_assignment.observability[0]' \
  -out=reserved-ip.tfplan

# Review the plan
tofu show reserved-ip.tfplan | less

# Apply only if the plan is clean (no Droplet replacement)
tofu apply reserved-ip.tfplan

# Confirm the Reserved IP is assigned
tofu output observability_public_ipv4
tofu output observability_reserved_ip_enabled
```

Then update Cloudflare A records to the Reserved IP address (one-time change). After this, future Droplet replacements will not require DNS updates.

---

## Controlled rebuild procedure (DO NOT RUN without review)

### Phase 0: Create a maintenance branch

```bash
cd /path/to/ixora-infra

git checkout develop
git pull origin develop
git checkout -b hotfix/observability-droplet-rebuild
```

### Phase 1: Temporarily disable `prevent_destroy`

Edit `opentofu/staging/observability.tf`.

Locate:

```hcl
  lifecycle {
    # Must be a literal — OpenTofu does not allow variables in prevent_destroy.
    prevent_destroy = true
    ignore_changes = [
      user_data,
    ]
  }
```

Change to:

```hcl
  lifecycle {
    # TEMPORARY: prevent_destroy disabled for controlled rebuild.
    # Restore to true immediately after tofu apply completes.
    prevent_destroy = false
    ignore_changes = [
      user_data,
    ]
  }
```

> **Important:** This change is narrowly scoped. Do not merge it to `develop` or `staging` with `prevent_destroy = false`. It must be restored before merging.

### Phase 2: Run `tofu fmt` and `tofu validate`

```bash
cd opentofu/staging
tofu fmt -recursive .
tofu validate
```

### Phase 3: Create a replacement plan

```bash
tofu plan \
  -replace='digitalocean_droplet.observability[0]' \
  -out=observability-rebuild.tfplan
```

### Phase 4: Review the plan (mandatory)

```bash
tofu show observability-rebuild.tfplan | less
```

The plan **must**:
- Show replacement of `digitalocean_droplet.observability[0]`
- Show update of `digitalocean_firewall.observability[0]` (attachment to new Droplet ID)
- Show update of `digitalocean_reserved_ip_assignment.observability[0]` if Reserved IP is enabled
- **Not** show replacement or destruction of any of the following:
  - `digitalocean_app.api`
  - `digitalocean_app.admin`
  - `digitalocean_database_cluster.postgres`
  - `digitalocean_database_db.app`
  - `digitalocean_database_user.app`
  - `digitalocean_database_firewall.postgres`
  - `digitalocean_spaces_bucket`

If the plan shows changes to unrelated resources (e.g. `digitalocean_app.api` due to encrypted-env drift), **do not apply blindly**. Evaluate whether the replacement can be safely isolated. If not, investigate and resolve the drift separately before rebuilding.

### Phase 5: Apply the saved plan

```bash
tofu apply observability-rebuild.tfplan
```

### Phase 6: Immediately restore `prevent_destroy = true`

Edit `opentofu/staging/observability.tf` — restore:

```hcl
  lifecycle {
    # Must be a literal — OpenTofu does not allow variables in prevent_destroy.
    prevent_destroy = true
    ignore_changes = [
      user_data,
    ]
  }
```

```bash
cd opentofu/staging
tofu plan   # must show no changes (confirm protect is active)
```

The plan must show `No changes` or only show infrastructure created in Phase 5 (if any final drift exists). The critical check is that `prevent_destroy = true` is active again.

### Phase 7: Get the new Droplet IP

```bash
tofu output observability_public_ipv4
tofu output observability_droplet_ipv4      # ephemeral IP, regardless of Reserved IP
tofu output observability_reserved_ip_enabled
```

### Phase 8: Update Cloudflare DNS (if no Reserved IP)

If `observability_reserved_ip_enabled = false`:

1. Log in to Cloudflare → `ixora-app.app` zone → DNS Records.
2. Update the `grafana-staging` A record to the new Droplet IPv4.
3. Update the `otel-staging` A record to the new Droplet IPv4.
4. Verify both records are **DNS only** (grey cloud, no Cloudflare proxy).
5. Wait 5–10 minutes for propagation before deploying.

If `observability_reserved_ip_enabled = true`: no DNS change is needed.

### Phase 9: Post-rebuild deployment

Cloud-init will bootstrap the new Droplet automatically. Verify it completed:

```bash
ssh root@<new-or-reserved-ip>
tail -30 /var/log/cloud-init-output.log
exit
```

Then follow the standard five-step deployment order:

```bash
# Step 1: Validate source (already done, but re-validate)
./scripts/validate-cloud-init.sh

# Step 2: Host was bootstrapped by cloud-init — skip repair script for a fresh Droplet
#         If cloud-init failed, run:
#         ./scripts/repair-observability-host.sh --host <ip> --user root

# Step 3: Sync repository files
./scripts/deploy-observability.sh \
  --host <new-or-reserved-ip> \
  --user root \
  --sync-only

# Step 4: Create collector/.env
ssh root@<new-or-reserved-ip>
cd /opt/ixora-observability
export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"
./scripts/bootstrap-collector-env.sh
exit

# Step 5: Full deployment
./scripts/deploy-observability.sh \
  --host <new-or-reserved-ip> \
  --user root
```

### Phase 10: Post-rebuild verification

From the new Droplet:

```bash
curl -fsS http://127.0.0.1:13133/health    # OTel Collector
curl -fsS http://127.0.0.1:9090/-/ready    # Prometheus
curl -fsS http://127.0.0.1:3100/ready      # Loki
curl -fsS http://127.0.0.1:3200/ready      # Tempo
curl -fsS http://127.0.0.1:3000/api/health # Grafana
```

From an external machine (after DNS propagates):

```bash
curl -I https://grafana-staging.ixora-app.app
# Expected: HTTP/2 200 or HTTP/2 302

curl -o /dev/null -w '%{http_code}\n' \
  https://otel-staging.ixora-app.app/v1/traces
# Expected: 401 or 405 (proves Caddy routing; 502 means Collector not running)
```

Verify no public bindings on internal ports:

```bash
ssh root@<ip>
ss -lntp | grep -E ':(3000|4317|4318|4319|9090|3100|3200) '
# All entries must show 127.0.0.1:<port>, never 0.0.0.0:<port>
```

### Phase 11: Commit and merge the maintenance branch

```bash
# On the maintenance branch, with prevent_destroy = true restored:
git add opentofu/staging/observability.tf
git commit -m "chore(infra): restore prevent_destroy after observability Droplet rebuild"

# Merge into develop
git checkout develop
git merge --no-ff hotfix/observability-droplet-rebuild
git push origin develop
git push origin hotfix/observability-droplet-rebuild   # keep branch for history
```

---

## Security follow-up after rebuild

A previously generated source archive reportedly contained:

- `.git/`
- `collector/.env`

The values in that archive must be treated as **potentially exposed**. Rotate the following secrets before bringing the rebuilt stack online:

| Secret | Where to rotate | Method |
|--------|----------------|--------|
| Grafana admin password (`GF_ADMIN_PASSWORD`) | `collector/.env` on host | Generate new value during Step 4 above |
| OTEL backend ingest key (`OTEL_INGEST_API_KEY_BACKEND`) | `collector/.env` + App Platform API env var | Generate new value during Step 4; update App Platform |
| OTEL mobile ingest key (`OTEL_INGEST_API_KEY_MOBILE`) | `collector/.env` + mobile build config | Generate new value during Step 4; update mobile secrets |
| DigitalOcean PAT (if in `.git/`) | DigitalOcean dashboard → API → Tokens | Revoke the old token; create a new one |

Do not print or log the existing values during rotation. Generate fresh values with `openssl rand`.

---

## Expected OpenTofu plan impact

A `tofu plan -replace='digitalocean_droplet.observability[0]'` should show:

| Resource | Action | Reason |
|----------|--------|--------|
| `digitalocean_droplet.observability[0]` | Replace (destroy + create) | `-replace` flag |
| `digitalocean_firewall.observability[0]` | Update in-place | New Droplet ID in `droplet_ids` |
| `digitalocean_reserved_ip_assignment.observability[0]` | Update in-place | New Droplet ID (only if Reserved IP enabled) |
| All other resources | No change | Unrelated |

The `digitalocean_app.api` resource may show perpetual drift from encrypted environment variables — this is a [known provider limitation](https://github.com/digitalocean/terraform-provider-digitalocean/issues/869) and is unrelated to the Droplet rebuild. Do not modify the API resource during this procedure.
