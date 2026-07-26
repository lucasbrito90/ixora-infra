# App Platform OTEL Integration — Phase 8.8.6

**Status:** Architecture design — **manual workflow today, automation future**  
**Constraint:** No App Platform resource changes in Phase 8.8.6  
**Collector endpoint:** `https://otel-staging.ixora-app.app` (Caddy → Collector :4318)

---

## 1. Current manual workflow

App Platform services (`back_vibes-api`, worker, scheduler) export OTLP to the observability Collector via **public HTTPS**.

### 1.1 Operator steps today

1. Deploy observability host (Phase 8.8.5)
2. Bootstrap `collector/.env` with `OTEL_INGEST_API_KEY_BACKEND`
3. Confirm Caddy routes `otel-staging.ixora-app.app` → Collector
4. In DigitalOcean App Platform console (or `api_secrets_extra` in tfvars):
   - Set `OTEL_EXPORTER_OTLP_ENDPOINT=https://otel-staging.ixora-app.app`
   - Set `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`
   - Set `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <backend-key>` (**encrypted**)
   - Set `OTEL_TRACES_EXPORTER=otlp`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`
5. Redeploy App Platform services
6. Verify traces in Tempo / metrics in Prometheus

### 1.2 Why manual in Phase 8.8.5

- Avoids unnecessary env block churn in `digitalocean_app.api` on every `tofu plan`
- Keeps OTEL ingest keys out of OpenTofu state
- Allows key rotation without infrastructure apply

### 1.3 Mobile (front_vibes)

| Variable | Value |
| --- | --- |
| Endpoint | Same HTTPS hostname |
| Auth header | `Authorization=Bearer <OTEL_INGEST_API_KEY_MOBILE>` |
| Protocol | `http/protobuf` |

Mobile keys are separate from backend keys — configured in app build env, not App Platform.

---

## 2. Variable ownership

| Variable | Owner today | Owner future | Secret? |
| --- | --- | --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Operator / DO console | OpenTofu (non-secret) | No |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Operator / DO console | OpenTofu | No |
| `OTEL_EXPORTER_OTLP_HEADERS` | Operator / DO console | OpenTofu `api_secrets_extra` or DO secret | **Yes** |
| `OTEL_SERVICE_NAME` | OpenTofu (per component) | OpenTofu | No |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTofu | OpenTofu | No |
| `OTEL_INGEST_API_KEY_BACKEND` | Host `collector/.env` | Host `.env` + synced to App Platform secret | **Yes** |
| `OTEL_INGEST_API_KEY_MOBILE` | Host `collector/.env` | Host `.env` only | **Yes** |

**Rule:** The Collector validates the Bearer token. App Platform and mobile must use keys that match `collector/.env`.

---

## 3. Future automated workflow (design)

```
┌─────────────────────────────────────────────────────────────┐
│ OpenTofu (opentofu/staging/)                                │
│  • observability_public_ipv4 / Reserved IP output           │
│  • observability_otlp_http_url = https://otel-staging...    │
│  • digitalocean_app.api env:                                │
│      OTEL_EXPORTER_OTLP_ENDPOINT (from output/local)        │
│      OTEL_EXPORTER_OTLP_PROTOCOL = http/protobuf            │
│  • api_secrets_extra:                                       │
│      OTEL_EXPORTER_OTLP_HEADERS (encrypted, from var/secret)│
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Observability host (separate apply path)                    │
│  • collector/.env: OTEL_INGEST_API_KEY_BACKEND              │
│  • Key MUST match App Platform header value                 │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Proposed OpenTofu pattern (future — not implemented)

```hcl
# CONCEPTUAL ONLY
locals {
  otel_endpoint = var.observability_enabled ? "https://${var.observability_otel_hostname}" : ""
}

# In app-api.tf service env block:
# OTEL_EXPORTER_OTLP_ENDPOINT = local.otel_endpoint
# OTEL_EXPORTER_OTLP_PROTOCOL   = "http/protobuf"

# In api_secrets_extra (sensitive, not in outputs):
# OTEL_EXPORTER_OTLP_HEADERS = "Authorization=Bearer ${var.otel_ingest_api_key_backend}"
```

### 3.2 Secret synchronization problem

The ingest key exists in **two places**:

1. Host `collector/.env` (Collector auth)
2. App Platform encrypted env (client auth)

**Future solutions (pick one in dedicated phase):**

| Approach | Pros | Cons |
| --- | --- | --- |
| Manual copy (current) | Simple; no state coupling | Drift risk on rotation |
| OpenTofu variable → both | Single apply | Key in OpenTofu state |
| DO Secrets Manager reference | No key in state | DO-specific; setup cost |
| Rotation runbook | Explicit process | Manual |

**Recommendation for production:** DO encrypted secret referenced by both App Platform and a secure host bootstrap — **not** plain tfvars.

---

## 4. Network path (unchanged)

```
App Platform (VPC-attached)
    → egress public internet
    → https://otel-staging.ixora-app.app:443
    → Caddy on observability Droplet
    → 127.0.0.1:4318 (Collector OTLP HTTP)
    → processors → Prometheus / Loki / Tempo
```

Private VPC routing to Droplet private IP is **not validated** — future phase if DO documents App Platform → VPC Droplet egress.

---

## 5. Implementation prerequisites (future phase)

- [ ] Observability host deployed and healthy
- [ ] OTLP HTTPS verified with test Bearer token
- [ ] Decision on secret storage (state vs DO secrets)
- [ ] Key rotation runbook
- [ ] Worker and scheduler confirmed using same endpoint
- [ ] Mobile SDK phase coordinated separately

---

## 6. What Phase 8.8.6 explicitly does not do

- ❌ Modify `digitalocean_app.api`
- ❌ Add OTEL env vars to OpenTofu
- ❌ Store ingest keys in state or outputs
- ❌ Change `back_vibes` telemetry code

---

## 7. Cross-references

| Document | Role |
| --- | --- |
| [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) § App Platform | Current manual table |
| [deployment-strategy.md](deployment-strategy.md) | Release deploy — endpoint unchanged |
| [observability-hardening.md](observability-hardening.md) | Hardening index |
| [back_vibes config/telemetry.php](https://github.com/lucasbrito90/back_vibes) | Application OTEL config |
