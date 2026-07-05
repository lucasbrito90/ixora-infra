# Feature Design Checklist

**Status:** Active architecture guide  
**Type:** Pre-spec checklist — **not** an ADR, **not** a Feature Specification  
**ADRs:** [ADR-026](../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)  
**Complements:** [`templates/feature-spec-template.md`](../templates/feature-spec-template.md) · [`domain-validation.md`](domain-validation.md) · [`asynchronous-orchestration.md`](asynchronous-orchestration.md)  
**Applies to:** All engineers and AI agents before writing a new Feature Specification

> **When to use:** Read and complete this checklist **before** copying the [Feature Specification Template](../templates/feature-spec-template.md). The answers feed directly into the spec — especially **Architecture Mapping**.

---

## 1. Purpose

This checklist exists to ensure engineers answer the **correct questions** before creating a Feature Specification. Many architecture problems in Ixora — duplicated services, duplicated jobs, fat controllers, unnecessary tables — are caused by **skipping design decisions** and jumping straight to implementation or spec writing.

Use this guide to:

- Frame the product problem and scope boundaries early
- Decide whether new domain entities, aggregates, or tables are justified
- Choose the correct async architecture layers **before** naming classes
- Surface security, failure, observability, and testing gaps while changes are still cheap

When followed consistently, this checklist reduces:

| Anti-pattern | How early design helps |
| --- | --- |
| **Duplicated services** | Forces reuse search before creating `*Service` |
| **Duplicated jobs** | Maps one unit of work per job; avoids parallel job classes doing the same thing |
| **Duplicated providers** | Isolates external I/O; reuses existing adapters |
| **Fat controllers** | Moves business rules to Domain Services |
| **Fat commands** | Keeps entrypoints thin per [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) |
| **Unnecessary entities** | Questions whether existing models (`Schedule`, `Vibe`, `Device`, etc.) suffice |
| **Over-engineering** | MVP and out-of-scope questions prevent premature abstraction |

**Output:** A completed checklist (inline in the spec draft, PR description, or design notes) that makes the Feature Spec's Architecture Mapping section straightforward to fill in.

---

## 2. Product Questions

Answer these before touching domain or architecture.

| # | Question | Notes |
| --- | --- | --- |
| 2.1 | **What user problem is being solved?** | One sentence. If unclear, stop — clarify with product. |
| 2.2 | **Is there a smaller MVP?** | What is the smallest shippable slice that delivers value? |
| 2.3 | **Is this replacing an existing feature?** | If yes, document migration/deprecation. |
| 2.4 | **Can existing components be reused?** | Screens, API endpoints, services, jobs, providers already in the codebase. |
| 2.5 | **What is explicitly OUT OF SCOPE?** | List deferred items — prevents scope creep in spec and review. |

**Red flags:**

- Cannot describe the user problem in one sentence
- MVP equals "build everything in the pitch deck"
- No out-of-scope list

---

## 3. Domain Questions

Decide **what** belongs in the domain model before naming tables or classes.

| # | Question | Notes |
| --- | --- | --- |
| 3.1 | **What entities participate?** | List existing and proposed entities. |
| 3.2 | **Do we really need a new table?** | Prefer composing existing schema (pivots, JSON columns, flags) when integrity allows. |
| 3.3 | **Can existing models solve this?** | Check `Schedule`, `Vibe`, `Device`, `ProviderConnection`, execution/audit tables, etc. |
| 3.4 | **Which existing aggregate does this belong to?** | See aggregate guide below. |
| 3.5 | **When is a new aggregate justified?** | See justification criteria below. |

### Existing aggregates (starting points)

| Aggregate | Typical ownership | Examples |
| --- | --- | --- |
| **Schedule** | User-owned recurrence / reminder | Scheduler MVP, automation triggers |
| **Vibe** | User-owned composition | Layers, device actions, playback metadata |
| **Device** | User-owned smart-home entity | HA entity mirror, online status |
| **ProviderConnection** | User-owned external link | Home Assistant base URL + token |
| **Execution / audit** | System-owned run records | `occurrence_key`, dispatch logs, idempotency |

If the feature does not fit any row, document **why** before proposing a new aggregate.

### When a new aggregate is justified

A new aggregate (and usually a new table) is justified when **all** apply:

- [ ] The concept has its **own lifecycle** independent of parent entities
- [ ] It has **invariants** that cannot be enforced on an existing model without breaking cohesion
- [ ] Multiple features will reference it — not a one-off column for a single screen
- [ ] Ownership boundaries are clear (`user_id` or system scope)

If only one or two criteria apply, prefer extending an existing aggregate.

---

## 4. Architecture Questions

> **Mandatory.** Every new feature must answer these before the Feature Spec is approved.

### 4.1 Entrypoint

| # | Question | Options |
| --- | --- | --- |
| 4.1.1 | **What is the Entrypoint?** | HTTP Controller · Queue Job · Console Command · Scheduler · Event Listener |
| 4.1.2 | **Is there more than one entrypoint?** | Document each (e.g. HTTP create + background dispatch). |
| 4.1.3 | **Does the entrypoint stay thin?** | Orchestration only — no business rules ([ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)). |

### 4.2 Layers

| # | Question | Reference |
| --- | --- | --- |
| 4.2.1 | **Is there a Domain Validator?** | Required for background paths touching user-owned resources — [ADR-026](../decisions/ADR-026-automation-execution-security.md), [`domain-validation.md`](domain-validation.md) |
| 4.2.2 | **Which Domain Service owns the business rules?** | New or existing? Name it. |
| 4.2.3 | **Are there Queue Jobs?** | One unit of work per job where possible |
| 4.2.4 | **Which Provider is used?** | HA, FCM, payment, etc. — or **None** |
| 4.2.5 | **Are external integrations isolated?** | Providers/adapters only — never in commands/controllers |

### 4.3 Architecture mapping preview

Before writing the spec, sketch the pipeline:

```
[Entrypoint] → [Domain Validator?] → [Domain Service] → [Queue Job?] → [Provider?]
```

If any box is "TBD" without a planned class name and responsibility, the design is not ready for a spec.

**Guides:**

- [ADR-026](../decisions/ADR-026-automation-execution-security.md) — security and ownership in async execution
- [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) — layering and anti-patterns
- [`asynchronous-orchestration.md`](asynchronous-orchestration.md) — implementation how-to

---

## 5. Security Questions

Complete for every feature — HTTP-only features still need ownership answers.

| # | Check | Detail |
| --- | --- | --- |
| 5.1 | **Does ownership exist?** | Which `user_id` (or system scope) owns each mutated resource? |
| 5.2 | **Can another user's resource be accessed?** | IDOR risks on read, update, delete, and **background replay** |
| 5.3 | **Will this execute in background?** | If yes → Domain Validator required ([ADR-026](../decisions/ADR-026-automation-execution-security.md)) |
| 5.4 | **Should Policies be used?** | HTTP path only — `Policy` + Form Request |
| 5.5 | **Should Domain Validators be used?** | Queue, scheduler, console, cron, listeners |
| 5.6 | **Could replay happen?** | Duplicate ticks, retried jobs, double-submit |
| 5.7 | **Is idempotency required?** | See [ADR-010](../decisions/ADR-010-scheduler-idempotency-occurrence-key.md) for occurrence-style keys |
| 5.8 | **Will secrets appear in logs?** | Tokens, LLATs, FCM keys, PII — safe logging only |

**Rules of thumb:**

- **HTTP:** Policies protect access. Form Requests validate input at write time.
- **Background:** Domain Validators protect execution. Never `Gate::authorize()` in jobs/commands.
- **Both layers** may be required when HTTP creates state that background later executes.

---

## 6. Failure Questions

For **every** feature, document behaviour per failure class. These answers become the spec's **Failure Policy** section.

| # | Scenario | Questions to answer |
| --- | --- | --- |
| 6.1 | **Validation fails** | Safe skip or error response? Roll back? Log fields? |
| 6.2 | **Queue unavailable** | Fail open, fail closed, sync fallback, or defer? |
| 6.3 | **Provider fails** | Retries (`$tries`, backoff)? Push on failure? Audit row? |
| 6.4 | **External API offline** | Timeout? Circuit breaker? User-visible message? |
| 6.5 | **Batch continues?** | One failure must not stop unrelated items when policy requires isolation |
| 6.6 | **Should retries happen?** | At job level, provider level, or not at all |
| 6.7 | **Should rollback happen?** | DB transaction scope; compensating actions |
| 6.8 | **Who logs?** | Entrypoint, service, job, provider — structured, safe IDs only |

**Default posture (async features):**

- Validator returns `false` → skip safely, no throw
- One side-effect failure → batch/recurrence continues unless spec says otherwise
- Provider failure → job retry boundary; domain service does not call HTTP directly

---

## 7. Observability Questions

| # | Check | Notes |
| --- | --- | --- |
| 7.1 | **Structured logs** | JSON or consistent key=value at layer boundaries |
| 7.2 | **Safe logging** | No secrets, tokens, or cross-user PII |
| 7.3 | **Metrics** | Counters/histograms if operational visibility is required |
| 7.4 | **Correlation IDs** | Future — note if cross-service tracing is needed |
| 7.5 | **Queue visibility** | Failed jobs, DLQ, horizon/dashboard expectations |
| 7.6 | **Audit trail** | Execution logs, occurrence keys, admin forensics |
| 7.7 | **Push notifications** | Which events notify the user? Failure only vs success |

---

## 8. Testing Questions

Answer **before** implementation — the spec's Test Strategy should reflect these decisions.

| Layer | Question |
| --- | --- |
| **Unit tests** | Validators, pure services, DTOs — what cases? |
| **Feature tests** | HTTP API, commands with `Bus::fake()` / queue fakes |
| **Integration tests** | Multi-component wiring (dispatcher + service + queue) |
| **Manual QA** | Staging checklist — who runs it? |
| **Android QA** | Device-specific behaviour (notifications, FGS, offline) |
| **Staging validation** | Required before merge to `develop` or before `staging` promote? |
| **E2E** | External system (HA, FCM) — scripted or manual evidence |
| **Failure scenarios** | Validator skip, provider timeout, queue down |
| **Ownership scenarios** | Cross-user access attempts (HTTP + background) |
| **Idempotency scenarios** | Duplicate tick, duplicate job, double POST |

**Minimum for async features:**

- [ ] Happy path
- [ ] Validator failure → safe skip
- [ ] Side-effect failure → batch isolation (if applicable)
- [ ] Idempotency / duplicate execution (if applicable)
- [ ] Ownership mismatch

---

## 9. Review Questions

> **Mandatory review** before approving any Feature Specification. Reviewers (human or AI) must confirm:

| # | Question | Pass criteria |
| --- | --- | --- |
| 9.1 | **Can this reuse an existing Service?** | Search codebase; justify new service if none fits |
| 9.2 | **Can this reuse an existing Validator?** | Extend before creating `*Validator` |
| 9.3 | **Is a new Job really necessary?** | Or can an existing job accept new payload/types? |
| 9.4 | **Is a new Provider really necessary?** | Or extend existing adapter interface? |
| 9.5 | **Is a new table really necessary?** | See §3 domain questions |
| 9.6 | **Could this feature be split into smaller phases?** | Each phase independently shippable and testable |
| 9.7 | **Is every async path documented?** | All entrypoints appear in Architecture Mapping |

**Block approval if:**

- Architecture Mapping has unjustified "TBD" layers
- Background path exists but no Domain Validator plan
- Business rules assigned to Command/Job/Controller without Domain Service
- Failure policy missing for any failure class in §6

---

## 10. Decision Tree

Use this flow when designing a new backend feature. Answer **yes/no** at each step.

```
Start: New feature needs backend work?
│
├─ No (client-only / read-only HTTP)?
│     └─► Document entrypoint = HTTP or mobile only.
│         Policies sufficient? → Spec → implement.
│
└─ Yes
      │
      ▼
Need background execution?
(queue, scheduler, cron, listener)
      │
      ├─ No → HTTP Controller entrypoint
      │         │
      │         ▼
      │     Need ownership validation?
      │         │
      │         ├─ Yes → Policy + Form Request
      │         └─ No  → Form Request / public endpoint (justify)
      │         │
      │         ▼
      │     Need business logic?
      │         │
      │         └─ Yes → Domain Service (keep controller thin)
      │
      └─ Yes → Async Entrypoint (Command / Job / Listener)
                │
                ▼
            Need ownership validation?
                │
                ├─ Yes → Domain Validator (NOT Policy)
                └─ No  → Justify (system-level, no user scope)
                │
                ▼
            Need business logic?
                │
                └─ Yes → Domain Service
                │
                ▼
            Need async unit of work with retries?
                │
                ├─ Yes → Queue Job (one unit per job)
                └─ No  → Service may enqueue or complete inline (justify)
                │
                ▼
            Need external system?
                │
                ├─ Yes → Provider / Adapter (isolated I/O)
                └─ No  → Done — map side effects in spec
```

**Short form:** Entrypoint → Validator? → Service → Job? → Provider?

---

## 11. Relationship with other documents

| Document | Role | How this checklist fits |
| --- | --- | --- |
| **[Feature Specification Template](../templates/feature-spec-template.md)** | Mandatory spec structure | **Read this checklist first**, then copy the template. Checklist answers populate Overview, Domain Model, and Architecture Mapping. |
| **[ADR-026](../decisions/ADR-026-automation-execution-security.md)** | *Why* Policies ≠ background security | §4 and §5 force Validator vs Policy decisions before spec approval. |
| **[ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md)** | *Why* thin entrypoints and layering | §4 and §9 enforce layer separation before naming classes. |
| **[domain-validation.md](domain-validation.md)** | *How* to write Domain Validators | Use when §4.2.1 or §5.5 answer "yes" to background validation. |
| **[asynchronous-orchestration.md](asynchronous-orchestration.md)** | *How* to implement async pipelines | Use when §4.3 pipeline is sketched — details layer responsibilities and anti-patterns. |

### Recommended workflow

```
1. Complete this checklist (§2–§9)
2. Copy Feature Specification Template → docs/specs/<domain>/<feature>/spec.md
3. Fill Architecture Mapping from §4 answers
4. Run §9 Review Questions (self + peer review)
5. Approve spec → implement in phases
```

**This document is not:**

- An ADR — it does not record a new architectural **decision**; it operationalizes existing ADRs.
- A Feature Spec — it has no acceptance criteria, API tables, or implementation phases.
- A substitute for reading ADR-026, ADR-027, or the implementation guides.

---

## Quick reference card

| Phase | Must answer |
| --- | --- |
| **Product** | Problem, MVP, reuse, out of scope |
| **Domain** | Entities, aggregates, new table justified? |
| **Architecture** | Entrypoint, Validator, Service, Job, Provider |
| **Security** | Ownership, Policies vs Validators, idempotency |
| **Failure** | Per-scenario behaviour |
| **Observability** | Logs, audit, push |
| **Testing** | Unit → E2E + failure/ownership/idempotency |
| **Review** | Reuse existing layers; split phases; document all async paths |

---

*Related index entry: [docs/README.md](../README.md) → Architecture → Cross-cutting.*
