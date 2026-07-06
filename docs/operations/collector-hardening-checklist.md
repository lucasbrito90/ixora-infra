# Collector Hardening Checklist

**Status:** Active operational checklist — apply at Phase 3 deployment  
**Scope:** OpenTelemetry Collector on observability staging VM  
**References:** [security-review.md](../specs/observability-foundation/mvp/security-review.md) · [infrastructure-review.md](../specs/observability-foundation/mvp/infrastructure-review.md) · [observability-operational-limits.md](../architecture/observability-operational-limits.md) · [collector-hardening source ADR-030](../../decisions/ADR-030-observability-security-and-privacy.md)

> **Purpose:** Pre-flight and post-deploy verification so Collector deployment is **mechanical** after Phase 2.5. Check each item during Phase 3; re-run after any Collector upgrade.

---

## 1. Pre-deploy

| # | Check | Pass criteria |
| --- | --- | --- |
| 1.1 | **Threat model reviewed** | [security-review.md](../specs/observability-foundation/mvp/security-review.md) acknowledged |
| 1.2 | **Ports documented** | Only 4317/4318 public for OTLP; backends internal ([infrastructure-review.md](../specs/observability-foundation/mvp/infrastructure-review.md) §5) |
| 1.3 | **API keys generated** | Separate staging keys; not in git |
| 1.4 | **TLS certificates** | Valid for `otel-staging.*` hostname |
| 1.5 | **VM sizing** | Meets [infrastructure-review.md](../specs/observability-foundation/mvp/infrastructure-review.md) §10 minimum |

---

## 2. Firewall

| # | Check | Pass criteria |
| --- | --- | --- |
| 2.1 | **Inbound 4317, 4318** | Open for App Platform + mobile (TLS) |
| 2.2 | **Inbound 9090, 3100, 3200** | **Closed** from internet |
| 2.3 | **Inbound 22 SSH** | Restricted to operator IPs |
| 2.4 | **Grafana HTTPS** | 443 or 3000 behind TLS proxy only |
| 2.5 | **Default deny** | No unnecessary open ports |

---

## 3. TLS

| # | Check | Pass criteria |
| --- | --- | --- |
| 3.1 | **OTLP TLS enabled** | No plain HTTP on public interface |
| 3.2 | **TLS 1.2+ only** | Legacy protocols disabled |
| 3.3 | **Certificate auto-renew** | certbot/Caddy scheduled |
| 3.4 | **Grafana TLS** | HTTPS for all UI access |

---

## 4. Authentication

| # | Check | Pass criteria |
| --- | --- | --- |
| 4.1 | **Auth extension enabled** | Invalid key rejected with 401 |
| 4.2 | **Missing key rejected** | Unauthenticated ingest fails |
| 4.3 | **Separate env keys** | Backend vs mobile keys optional but documented |
| 4.4 | **Key not in config file committed to git** | Env var reference only |

---

## 5. Receivers

| # | Check | Pass criteria |
| --- | --- | --- |
| 5.1 | **OTLP gRPC + HTTP only** | No unused receivers (Jaeger, Zipkin, etc.) |
| 5.2 | **Receiver validation** | Malformed payload does not crash Collector |
| 5.3 | **Disabled receivers** | Explicitly not configured — no open legacy ports |
| 5.4 | **Bind address** | Public receivers on intended interface only |

---

## 6. Processors

| # | Check | Pass criteria |
| --- | --- | --- |
| 6.1 | **Redaction processor** | Drops forbidden keys per [security-review.md](../specs/observability-foundation/mvp/security-review.md) §8 |
| 6.2 | **Sampling processor** | Matches ADR-031 rates |
| 6.3 | **Attributes / label allowlist** | High-cardinality labels dropped before Prometheus |
| 6.4 | **Memory limiter** | Configured per [observability-operational-limits.md](../architecture/observability-operational-limits.md) |
| 6.5 | **Batch processor** | Batch size and timeout set |

---

## 7. Exporters

| # | Check | Pass criteria |
| --- | --- | --- |
| 7.1 | **Only required exporters** | Prometheus, Loki, Tempo — no debug exporters to public |
| 7.2 | **Disabled exporters** | `logging` exporter debug off in production/staging steady state |
| 7.3 | **Localhost endpoints** | Backend URLs use `127.0.0.1` |
| 7.4 | **Retry + timeout** | Bounded per operational limits |

---

## 8. Health and readiness

| # | Check | Pass criteria |
| --- | --- | --- |
| 8.1 | **Health extension** | `:13133` returns OK when healthy |
| 8.2 | **Readiness** | Fails when exporters unreachable (optional) |
| 8.3 | **Self-metrics** | Collector exports own metrics for monitoring |
| 8.4 | **Logging level** | `info` default — `debug` only during troubleshooting |

---

## 9. OS and service

| # | Check | Pass criteria |
| --- | --- | --- |
| 9.1 | **Dedicated service user** | Collector not running as root |
| 9.2 | **Disk permissions** | Config readable; secrets `chmod 600` |
| 9.3 | **OS updates** | Unattended security patches or monthly patch window |
| 9.4 | **Restart policy** | `systemd` `Restart=on-failure` |
| 9.5 | **Least privilege** | Service account cannot SSH or write outside data dirs |
| 9.6 | **Secure defaults** | No default admin passwords on any component |

---

## 10. Backups and recovery

| # | Check | Pass criteria |
| --- | --- | --- |
| 10.1 | **Collector config in git** | `ixora-infra` — not VM-only |
| 10.2 | **VM snapshot policy** | Documented (optional weekly) |
| 10.3 | **Recovery tested** | Redeploy Collector from config succeeds |
| 10.4 | **Secrets recovery** | Keys rotatable from DO without git |

---

## 11. Validation tests (Phase 3)

| # | Test | Expected |
| --- | --- | --- |
| 11.1 | Valid key + test span | Accepted; appears in Tempo/Loki after backends up |
| 11.2 | Invalid key | 401; no data stored |
| 11.3 | Span with `Authorization` attribute | Redacted or dropped |
| 11.4 | Collector stopped | `back_vibes` health still OK ([telemetry-availability-policy.md](../architecture/telemetry-availability-policy.md)) |
| 11.5 | Flood test (manual) | Collector drops; VM stays up |

---

## 12. Future HA considerations (not MVP)

| Item | Notes |
| --- | --- |
| Collector replica set | Behind load balancer; shared auth keys |
| Config sync | GitOps or config management |
| Zero-downtime deploy | Rolling Collector restart |
| mTLS for backend clients | See [security-review.md](../specs/observability-foundation/mvp/security-review.md) §3 |

---

## Sign-off

| Role | Phase 3 sign-off |
| --- | --- |
| Infra ops | Firewall + TLS + VM |
| Backend lead | Auth + redaction spot check |
| Security | ADR-030 sample telemetry review |

**Related:** [observability-playbook.md](observability-playbook.md) · [plan.md](../specs/observability-foundation/mvp/plan.md) Phase 3
