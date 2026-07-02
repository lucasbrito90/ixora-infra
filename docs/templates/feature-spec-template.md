# Feature Specification — [Feature Name]

**Status:** Draft  
**Version:** 0.1  
**Feature ID:** `[domain]/[feature-name]`  
**Platform:** `back_vibes` · `front_vibes` · `ixora-admin` *(list applicable repos)*

> **Mandatory template.** All new Ixora feature specifications must start from this file. Copy to `docs/specs/<domain>/<feature>/spec.md` and fill every section before implementation begins.
>
> **Before this template:** Complete the [Feature Design Checklist](../architecture/feature-design-checklist.md) — product, domain, architecture, security, failure, observability, testing, and review questions. Checklist answers feed directly into this spec.
>
> **Architecture first:** No feature may start runtime implementation until **Architecture Mapping** is complete. See [ADR-026](../decisions/ADR-026-automation-execution-security.md), [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md), [`domain-validation.md`](../architecture/domain-validation.md), [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md).

---

# Overview

<!-- Describe the feature goal in 2–4 sentences. What user or system problem does this solve? -->

[Feature objective — what we are building and why.]

---

# Goals

<!-- What success looks like. Be specific and measurable where possible. -->

- [ ] Goal 1
- [ ] Goal 2
- [ ] Goal 3

---

# Non Goals

<!-- Explicitly out of scope for this feature — prevents scope creep. -->

- Not building …
- Not changing …
- Not integrating …

---

# Scope

<!-- What is included in this delivery. -->

| Capability | In scope |
| --- | --- |
| … | ✅ / ❌ |

---

# Out of Scope

<!-- Deferred to future phases or other features. -->

- …

---

# User Stories

*(Optional)*

<!-- As a [role], I want [action], so that [benefit]. -->

1. As a …, I want …, so that …
2. …

---

# Domain Model

<!-- Entities, relationships, and key fields involved. Link to existing models where applicable. -->

| Entity | Role in this feature |
| --- | --- |
| … | … |

**Relationships:**

```
[Entity A] ──► [Entity B] ──► [Entity C]
```

---

# API Changes

*(If applicable — otherwise write "None")*

<!-- New or changed endpoints, request/response shapes, authorization. -->

| Method | Path | Change |
| --- | --- | --- |
| … | … | … |

---

# Mobile Changes

*(If applicable — otherwise write "None")*

<!-- Screens, composables, local notifications, offline behaviour. -->

- …

---

# Database Changes

*(If applicable — otherwise write "None")*

<!-- Migrations, indexes, constraints. Prefer "None" when composing existing schema. -->

| Change | Rationale |
| --- | --- |
| … | … |

---

# Architecture Mapping

> **Required.** Map this feature to the Ixora async architecture layers before writing code. See [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md).

---

## Async Entrypoint

<!-- Which component initiates the flow? List all entry points (HTTP + background). -->

| Entrypoint | Type | Trigger |
| --- | --- | --- |
| … | Console Command / HTTP Controller / Queue Job / Cron / Event Listener | … |

**Primary async entrypoint:** `[ClassName or route]` — *[one-line description]*

If not applicable (purely synchronous HTTP with no background path):

**Not applicable** — *[explain why — e.g. read-only API, client-only feature]*

---

## Domain Validator

<!-- Does a Domain Validator exist? Required for all background paths that touch user-owned resources (ADR-026). -->

| Validator | Validates | Return contract |
| --- | --- | --- |
| … | ownership / integrity / idempotency gate | `bool` — `false` = skip safely, no throw |

If not applicable:

**Not applicable** — *[explain why — e.g. no async execution, HTTP-only with Policy sufficient, system-level job with no user scope]*

Reference: [`domain-validation.md`](../architecture/domain-validation.md)

---

## Domain Service

<!-- Which service(s) contain domain intent / business rules? -->

| Service | Domain intent |
| --- | --- |
| … | … |

If none yet (new feature):

**TBD** — *[describe planned service name and responsibility]*

---

## Queue Jobs

<!-- Which jobs participate? One unit of work per job where possible. -->

| Job | Queue | Unit of work |
| --- | --- | --- |
| … | … | … |

Or:

**None** — *[explain — e.g. synchronous HTTP only, or side effects inline in service with justification]*

---

## Providers / Adapters

<!-- External integrations — HTTP, SDK, FCM, payment, etc. -->

| Provider / Adapter | External system |
| --- | --- |
| … | … |

Or:

**None** — *[no external I/O in this feature]*

---

## Side Effects

<!-- List ALL side effects — DB writes, enqueue, push, logs, analytics, file storage. -->

| Side effect | When | Layer |
| --- | --- | --- |
| Creates … | … | Entrypoint / Service / Job |
| Enqueues … | … | Service |
| Sends push notification | … | Job / Events |
| Updates audit log | … | Entrypoint |
| … | … | … |

---

## Failure Policy

<!-- Answer each scenario explicitly. Reference ADR-023 where recurrence/batch isolation applies. -->

### Validator failure

| Behaviour | Detail |
| --- | --- |
| Roll back DB? | Yes / No — *[when]* |
| Emit push? | Yes / No |
| Stop batch? | Yes / No |
| Log? | Yes — *[fields]* |

### Domain Service exception

| Behaviour | Detail |
| --- | --- |
| Propagate to entrypoint catch? | Yes / No |
| Roll back committed state? | Yes / No |
| … | … |

### Queue unavailable

| Behaviour | Detail |
| --- | --- |
| … | … |

### Provider failure

| Behaviour | Detail |
| --- | --- |
| Retry? | Job `$tries` = … |
| Push on failure? | Yes / No — event type |
| … | … |

### Batch failure

| Behaviour | Detail |
| --- | --- |
| One item fails → others continue? | Yes / No |
| … | … |

---

## Idempotency

<!-- How is duplicate execution prevented? -->

| Mechanism | Scope |
| --- | --- |
| … | … |

Examples: `occurrence_key`, unique index, provider idempotency key, job deduplication.

Or:

**None** — *[justify — e.g. read-only, naturally idempotent operation]*

Reference: [ADR-010](../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) where applicable.

---

## Security Boundary

<!-- ADR-026: Policies for HTTP; Domain Validators for async. -->

**HTTP path:**

| Resource | Mechanism |
| --- | --- |
| … | `Policy` / Form Request |

**Background path:**

| Execution | Validator | Why |
| --- | --- | --- |
| … | … | … |

Or:

**Validator not required** — *[justify — e.g. no background execution, no user-owned resource mutation outside HTTP]*

Reference: [ADR-026](../decisions/ADR-026-automation-execution-security.md)

---

## Related ADRs

<!-- List all ADRs relevant to this feature. -->

| ADR | Relevance |
| --- | --- |
| [ADR-010](../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) | … |
| [ADR-016](../decisions/ADR-016-smart-home-async-execution.md) | … |
| [ADR-017](../decisions/ADR-017-push-notification-provider-strategy.md) | … |
| [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) | … |
| [ADR-026](../decisions/ADR-026-automation-execution-security.md) | … |
| [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) | … |

---

# Implementation Plan

<!-- Small phases — each independently implementable and verifiable. Prefer `plan.md` for detail. -->

## Implementation Phases

| Phase | Deliverable | Status |
| --- | --- | --- |
| 1 — Spec + ADRs | This document + decisions | Pending |
| 2 — … | … | Pending |
| 3 — … | … | Pending |

Each phase should:

- Have a clear **Done** definition
- Avoid mixing unrelated concerns
- Reference Architecture Mapping layers explicitly

---

# Test Strategy

| Layer | Scope | Location |
| --- | --- | --- |
| **Unit tests** | Validators, pure services, DTOs | `tests/Unit/…` |
| **Feature tests** | HTTP API, commands with `Bus::fake()` | `tests/Feature/…` |
| **Integration tests** | Multi-component wiring (dispatcher + service + queue) | `tests/Feature/…` |
| **Manual QA** | Staging checklist | `docs/qa/…` or spec appendix |
| **E2E** | Device / external system validation | QA scripts |

### Required test cases (minimum)

- [ ] Happy path
- [ ] Validator failure → safe skip
- [ ] Side-effect failure → batch/recurrence isolation (if applicable)
- [ ] Idempotency / duplicate tick (if applicable)
- [ ] Ownership mismatch (if user-scoped)

---

# Acceptance Criteria

<!-- Checklist for feature complete. -->

- [ ] …
- [ ] Architecture Mapping implemented as documented
- [ ] All tests passing on `develop`
- [ ] Staging verified (if applicable)
- [ ] `tasks.md` updated

---

# Review Checklist

<!-- Mandatory architectural review before merge to develop. -->

- [ ] Async Entrypoint clearly defined (or N/A justified)
- [ ] Domain Validator defined (or N/A justified per ADR-026)
- [ ] Domain Service defined
- [ ] Queue Jobs documented (or None justified)
- [ ] Providers / Adapters documented (or None)
- [ ] All side effects listed
- [ ] Failure policy defined for each failure class
- [ ] Idempotency strategy defined (or None justified)
- [ ] Security boundary documented (Policy + Validator)
- [ ] Related ADRs listed and honoured
- [ ] No business rules planned inside Command/Job entrypoints ([ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md))
- [ ] No `Gate::authorize()` in background paths
- [ ] No direct provider/HTTP calls from Commands
- [ ] Implementation phases are small and isolated

---

# Important notes

> **This template is mandatory for any new feature on the Ixora platform.**
>
> The intent is to ensure **architectural consistency** across Scheduler, Smart Home, Push Notifications, Analytics, Marketplace, Admin, and all future modules.
>
> **No feature may begin runtime implementation until the Architecture Mapping section is fully completed and reviewed.**
>
> Guides: [`feature-design-checklist.md`](../architecture/feature-design-checklist.md) · [`asynchronous-orchestration.md`](../architecture/asynchronous-orchestration.md) · [`domain-validation.md`](../architecture/domain-validation.md)

---

## Example reference specs

| Feature | Spec path |
| --- | --- |
| Scheduler + Smart Home Automations | [`specs/scheduler-smart-home-automations/mvp/spec.md`](../specs/scheduler-smart-home-automations/mvp/spec.md) |
| Smart Home MVP | [`specs/smart-home/mvp/spec.md`](../specs/smart-home/mvp/spec.md) |
| Push Notifications MVP | [`specs/push-notifications/mvp/spec.md`](../specs/push-notifications/mvp/spec.md) |

*Existing specs predating this template may be migrated opportunistically — all **new** specs must use this template from day one.*
