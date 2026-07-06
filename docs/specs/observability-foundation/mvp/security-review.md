# Observability Foundation — Security Review

**Status:** Phase 2.5 complete — documentation only  
**Spec:** [`spec.md`](spec.md) · **Infrastructure:** [`infrastructure-review.md`](infrastructure-review.md)  
**ADRs:** [ADR-028](../../../decisions/ADR-028-observability-platform.md) · [ADR-029](../../../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Applies to:** Staging MVP observability stack — **review only**; no Collector config in this phase

> **Rule of thumb:** Security is enforced in **three lines** — application discipline, Collector processors, and access control on Grafana/backends. This document makes Phase 3 Collector deployment almost mechanical.

---

## 1. Threat model

### Assets

| Asset | Value | Location |
| --- | --- | --- |
| Telemetry data (logs, traces, metrics) | Operational insight; may contain `user_id` | Loki, Tempo, Prometheus |
| OTLP ingest endpoint | Entry point for all signals | Collector `:4317` / `:4318` |
| Grafana | Query UI; team-wide read access | `:443` / `:3000` |
| Observability VM | Hosts entire stack | DigitalOcean Droplet |
| OTLP API keys | Authenticate app ingest | App Platform secrets + mobile build config |

### Threat catalog

| Threat | Description | Impact | MVP mitigations |
| --- | --- | --- | --- |
| **Public OTLP endpoint abuse** | Attacker discovers Collector URL and sends junk | Disk fill, noise, cost | TLS + API key; firewall IP allowlist where feasible; rate limiting (Phase 3+) |
| **Telemetry flooding** | High-volume OTLP from compromised or misconfigured client | DoS on VM; storage exhaustion | Batch limits; memory limiter; sampling; disk alerts ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| **Malformed payloads** | Invalid OTLP/protobuf causing Collector panic | Ingest outage | Receiver validation; Collector version pinning; health checks |
| **Replay attempts** | Re-sending captured OTLP batches | Duplicate noise; misleading traces | API key rotation; short-lived keys per env; no sensitive data in payloads anyway |
| **Credential leakage** | Secrets in logs/traces or git | Account takeover; HA/FCM abuse | ADR-030; app + Collector redaction; secrets in DO only |
| **Unauthorized Grafana access** | Public Grafana without auth | Full log/trace read including `user_id` | Mandatory auth; HTTPS; not public without login |
| **Denial of service** | Sustained ingest or query load | Stack unavailable | Product unaffected ([telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md)); VM isolation |
| **Excessive cardinality attacks** | Labels like `user_id` on every metric series | Prometheus OOM / disk | Label allowlist at Collector; ADR-031 caps |
| **Telemetry poisoning** | Fake `service.name` or `deployment.environment` | Misleading dashboards | API key scoped to env; validate `service.name` allowlist at Collector |
| **Fake traces** | Spans impersonating `back_vibes-api` | False incident data | Auth on ingest; correlate with known App Platform egress |
| **Fake metrics** | Counter spikes on `ixora.*` | False alerts (post-MVP) | Same as fake traces |
| **Fake logs** | Log lines with forged `trace_id` | Broken correlation | Auth on ingest; structured schema validation |

### Threat actors

| Actor | Capability | Primary concern |
| --- | --- | --- |
| Internet anonymous | OTLP URL discovery | Flooding, poisoning |
| Compromised mobile APK | Valid API key in build | Flooding from devices |
| Compromised App Platform env | Valid backend key | Credential + telemetry leak |
| Insider (engineering) | Grafana + SSH | Over-broad data access — acceptable with policy |
| Malicious engineer | SSH + backends | Direct Loki/Tempo read — restrict SSH |

---

## 2. Trust boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│  UNTRUSTED (from Collector's perspective)                        │
│  back_vibes · front_vibes-android · Internet                     │
└────────────────────────────┬────────────────────────────────────┘
                             │ OTLP + TLS + API Key
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY 1 — Collector ingress                            │
│  Assumption: authenticated clients only; payloads may contain   │
│  mistakes (PII) — never fully trusted                            │
└────────────────────────────┬────────────────────────────────────┘
                             │ processed OTLP (redacted, sampled)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY 2 — localhost backends                           │
│  Prometheus · Loki · Tempo                                       │
│  Assumption: only Collector writes; no app access                │
└────────────────────────────┬────────────────────────────────────┘
                             │ query APIs (internal)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY 3 — Grafana                                      │
│  Assumption: authenticated engineers; read-only on backends      │
└─────────────────────────────────────────────────────────────────┘
```

| Boundary | Trust assumption | Verification |
| --- | --- | --- |
| **Apps → Collector** | Client holds valid API key; payload may leak PII by mistake | Auth extension; redaction processor |
| **Collector → Backends** | Collector output is sanitized | Processor tests; spot checks |
| **Backends → Grafana** | Data at rest is team-readable | Grafana RBAC; env-separated datasources |
| **Apps → Backends** | **Must never happen** | Firewall; no credentials in apps ([ADR-028](../../../decisions/ADR-028-observability-platform.md)) |
| **Apps → Product DB** | Separate trust domain | Observability never queries Postgres |

---

## 3. Authentication strategy

### How applications authenticate with Collector

Applications send OTLP over **HTTPS/TLS** with a static **OTLP API Key** in a header:

| Client | Header | Secret storage |
| --- | --- | --- |
| `back_vibes-api` / worker | `Authorization: Bearer <OTEL_API_KEY>` or `X-Otel-Api-Key` | App Platform encrypted env |
| `front_vibes-android` | Same header | Build-time staging secret (not in git) |

Collector **`auth` extension** (or equivalent) validates key before accepting spans/logs/metrics.

### Comparison

| Approach | Pros | Cons | MVP fit |
| --- | --- | --- | --- |
| **OTLP API Keys** | Simple; works for mobile + App Platform; easy rotation | Key in mobile APK extractable; shared secret | ✅ **Chosen for MVP** |
| **mTLS** | Strong client identity; no shared bearer secret | Hard on Capacitor/mobile; cert lifecycle heavy | Deferred — backend-only candidate |
| **Private networking only** | Reduces exposure | Mobile cannot use VPC; App Platform egress still needs public endpoint | **Complement**, not sole control |

### MVP decision: OTLP API Keys + TLS

**Why:**

1. Mobile staging APK must reach Collector over internet — mTLS impractical for MVP.
2. App Platform workers egress to public Collector hostname ([infrastructure-review.md](infrastructure-review.md) §5).
3. Single shared staging key rotatable via env rebuild — acceptable homologation risk.
4. Implements faster than PKI; unblocks Phase 3.

**Hardening layers (MVP):**

- TLS 1.2+ required on `:4318` / `:4317`
- Separate API keys per `deployment.environment` (`staging` ≠ `production`)
- Optional firewall allowlist for App Platform egress IPs (document in Phase 3)
- Separate mobile vs backend keys (optional — limits blast radius if APK extracted)

### Future migration path

| Stage | Evolution |
| --- | --- |
| **MVP** | API key + TLS |
| **Backend hardening** | mTLS for App Platform → Collector (mobile stays API key) |
| **Production** | Short-lived tokens via sidecar or secret broker — new ADR |
| **Managed ingest** | Grafana Cloud / vendor OTLP with OAuth — migration ADR |

---

## 4. Authorization

| Action | Who may | How enforced |
| --- | --- | --- |
| **Send telemetry** | `back_vibes-*`, `front_vibes-android` with valid API key | Collector auth extension |
| **Read dashboards** | Engineering team (authenticated Grafana users) | Grafana org role `Viewer`+ |
| **Access Explore** | Engineering team | Grafana `Editor` or `Viewer` with Explore enabled |
| **Grafana Admin** | Platform ops / lead engineers only | Grafana `Admin` role — ≤ 2 accounts MVP |
| **SSH into VM** | Infra operators only | DO firewall + SSH key; not whole team |
| **Read Loki directly** | Break-glass ops via SSH + localhost | No public `:3100`; not for routine debugging |
| **Read Tempo directly** | Break-glass ops via SSH + localhost | No public `:3200` |
| **Read Prometheus directly** | Break-glass ops via SSH + localhost | No public `:9090` |

**Routine debugging:** Grafana only — not direct backend APIs.

**Environment separation:** Staging Grafana datasources **must not** point at production backends (when production exists).

---

## 5. TLS policy

| Surface | TLS required | Certificate | Notes |
| --- | --- | --- | --- |
| **Collector OTLP** (`4317` gRPC, `4318` HTTP) | ✅ Yes | Let's Encrypt or DO-managed | Public ingest |
| **Grafana UI** | ✅ Yes | Let's Encrypt | Reverse proxy (Caddy/nginx) recommended |
| **Prometheus / Loki / Tempo** | N/A (localhost HTTP) | — | Never expose publicly |
| **Collector → backends** | Optional localhost | — | Same VM; HTTP on `127.0.0.1` acceptable MVP |

### Protocols

| Allowed | Forbidden |
| --- | --- |
| TLS 1.2, TLS 1.3 | TLS 1.0, TLS 1.1, plain HTTP on public OTLP |
| Modern cipher suites | NULL, EXPORT ciphers |

### Certificate renewal

| Method | Owner |
| --- | --- |
| **Let's Encrypt auto-renew** via Caddy or certbot cron | Infra ops — Phase 3 |
| **Monitor expiry** | Alert 14 days before (Phase 10 runbook) |

Hostnames (reserved): `otel-staging.ixora-app.app`, `grafana-staging.ixora-app.app` ([infrastructure-review.md](infrastructure-review.md) §5).

---

## 6. Secrets handling

### Where secrets live

| Secret | Storage | Never in |
| --- | --- | --- |
| `OTEL_API_KEY` (backend) | App Platform encrypted env | Git, logs, traces |
| `OTEL_API_KEY` (mobile staging) | CI/build secret → bundled env | Git, public repo |
| Grafana admin password | DO secrets / env on VM | Git |
| TLS private keys | VM filesystem (restricted perms) | Git |
| SSH keys | Operator machines + DO | Git |

### DigitalOcean boundaries

| System | Secrets |
| --- | --- |
| **App Platform** | `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_API_KEY`, existing `FIREBASE_*` — separate from observability VM |
| **Observability Droplet** | Collector config references env vars; API key validation list; Grafana creds |
| **OpenTofu** | **No observability secrets in Phase 2.5/3 MVP** — manual Droplet or future IaC ADR |

### Future Secret Manager migration

| Stage | Approach |
| --- | --- |
| MVP | DO App Platform secrets + VM env files (`chmod 600`) |
| Growth | HashiCorp Vault, DO Secrets, or 1Password Connect — ADR required |
| Rotation | API key rotation without redeploy — requires secret manager |

**Rule:** Secrets **never** appear in telemetry payloads ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)).

---

## 7. PII review

Expands [ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md) with field-level guidance for Ixora domains.

### Allowed

| Field | Context | Example |
| --- | --- | --- |
| `user_id` | Log/trace attribute | `123` |
| `schedule_id`, `vibe_id`, `device_id` | Log/trace attribute | integers |
| `service.name`, `deployment.environment` | Resource attribute | `back_vibes-worker`, `staging` |
| `trace_id`, `span_id` | Correlation | W3C hex |
| `exception_class` | Errors | `ProviderConnectionException` |
| `error` (sanitized) | Human message | `Connection timed out` |
| `notification.type` | Push/Smart Home | `smart_home_action_failed` |
| `outcome` | Domain result | `failure` |
| `http.route`, `http.status_code` | HTTP spans | `/api/v1/schedules`, `502` |
| `queue.name`, `job.name` | Queue spans | `smart-home`, `SmartHomeActionJob` |
| Device OS / app version | Mobile resource | `Android 15`, `1.2.0` |

### Forbidden

| Field | Why |
| --- | --- |
| Email, name, phone | Direct PII |
| `firebase_uid` | Use `user_id` only |
| Full FCM / HA tokens | Credential |
| `Authorization` header value | Credential |
| Raw SQL with user data | May embed PII |
| User email in span **name** | Searchable PII in Tempo UI |
| Full provider response bodies | May contain tokens or home layout |

### Borderline

| Field | Guidance |
| --- | --- |
| **IP address** | Avoid; hash if abuse debugging requires it — never mobile |
| **Vibe/schedule title** | Prefer IDs only in telemetry; titles in product DB |
| **HA entity ID** (`light.bedroom`) | Avoid — use `device_id` integer; entity IDs reveal home layout |
| **Push token last 4 chars** | Correlation only in backend logs if needed — never traces/metrics |
| **`user_id` as metric label** | ❌ Forbidden — high cardinality + privacy aggregation risk |

### Laravel examples

**✅ Safe:**

```php
Log::warning('SmartHomeActionJob: action execution failed', [
    'schedule_id' => $scheduleId,
    'device_id' => $deviceId,
    'user_id' => $userId,
    'exception_class' => $e::class,
    'trace_id' => $traceId,
]);
```

**❌ Unsafe:**

```php
Log::error('HA failed', [
    'authorization' => $request->header('Authorization'),
    'ha_response' => $response->body(),
    'user_email' => $user->email,
]);
```

### Mobile examples

**✅ Safe:** `service.name=front_vibes-android`, screen span name, sanitized error class, `user_id` if already in app context (integer only).

**❌ Unsafe:** Firebase ID token, FCM token, user display name, email, full API error bodies from HA proxy.

Aligns with [notification-architecture.md](../../../architecture/notification-architecture.md) and [ADR-021](../../../decisions/ADR-021-notification-security-and-privacy.md).

---

## 8. Redaction strategy

### Defense in depth

| Layer | Responsibility | Phase |
| --- | --- | --- |
| **Application** | Never emit forbidden fields; sanitize exception messages | 7–8 |
| **Collector processors** | Drop/redact keys matching patterns; strip Bearer/JWT regex | 3 |
| **Storage** | Retention limits exposure window | 4–6 |
| **Query time (Grafana)** | RBAC; no public dashboards | 9 |

### Application side

- Laravel: never pass secrets to `Log::` context; use existing automation log patterns ([ADR-024](../../../decisions/ADR-024-automation-notifications-and-observability.md)).
- Mobile: OTel SDK attribute allowlist; no HTTP header recording.

### Collector processors (Phase 3 requirements)

| Processor | Function |
| --- | --- |
| **`attributes`** | Delete keys: `password`, `token`, `authorization`, `secret`, `credential`, `api_key`, `private_key`, `fcm_token`, `ha_token` |
| **`transform` / regex** | Redact `Bearer eyJ...`, JWT-shaped strings in log bodies |
| **`filter`** | Drop spans with unknown `service.name` (optional allowlist) |
| **`probabilistic_sampler`** | Per ADR-031 |

### Why Collector is the second line of defense

Applications will make mistakes. Collector catches:

- Accidental `Authorization` in log export
- Third-party library auto-instrumentation leaking headers
- Mobile SDK default HTTP instrumentation

**Without Collector redaction**, one bad deploy writes secrets to Loki for 14 days.

### Storage and query time

- Retention caps ([ADR-031](../../../decisions/ADR-031-retention-storage-and-cost-control.md)) limit breach window.
- Grafana: no anonymous access; audit log export (post-MVP).

---

## 9. Rate limiting

**No implementation in Phase 2.5** — architectural recommendations for Phase 3+.

| Layer | Recommendation |
| --- | --- |
| **Collector ingress** | `memory_limiter` + `queued_retry` with max queue size ([observability-operational-limits.md](../../../architecture/observability-operational-limits.md)) |
| **Network ingress** | DO Cloud Firewall connection rate limits if available; fail2ban on repeated bad auth |
| **API keys** | Separate keys per client class; rotate on leak; reject missing/invalid key immediately |
| **DoS protection** | No unauthenticated OTLP; sampling under load; drop telemetry before OOM — **never** block apps |
| **Grafana** | Query timeout; max concurrent queries per user |

Under flood: **drop telemetry**, not product traffic ([telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md)).

---

## Phase 2.5 exit criteria

- [x] Threat model documented
- [x] Trust boundaries defined
- [x] Authentication strategy: **OTLP API Keys + TLS** (MVP)
- [x] Authorization matrix published
- [x] TLS policy documented
- [x] Secrets handling documented
- [x] PII review expanded from ADR-030
- [x] Redaction strategy (app + Collector) documented
- [x] Rate limiting recommendations documented
- [x] **No runtime code or Collector config created**

**Next:** [Phase 3 — Collector Deployment](plan.md) using [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md).

---

## Related documents

| Document | Relationship |
| --- | --- |
| [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) | Failure isolation under attack/load |
| [observability-operational-limits.md](../../../architecture/observability-operational-limits.md) | Queue/batch limits |
| [collector-hardening-checklist.md](../../../operations/collector-hardening-checklist.md) | Phase 3 deployment checklist |
| [infrastructure-review.md](infrastructure-review.md) | Ports and firewall intent |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | Forbidden metric labels |
