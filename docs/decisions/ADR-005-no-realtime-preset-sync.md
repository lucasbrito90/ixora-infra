# ADR-005: No realtime synchronization between presets and imported vibes

## Status

**Accepted** — reflects **current shipped behaviour** and intentional absence of sync infrastructure.

## Date

2026-05-23

## Context

Ixora separates **catalog templates** (`preset_vibes`, `preset_vibe_sounds`) from **user-owned compositions** (`vibes`, `vibe_sounds`). Users import presets via a **one-time copy** ([ADR-003](ADR-003-preset-import-independent-vibes.md)); afterward the user vibe is a normal row under **`VibePolicy`**, played through the standard mobile runtime ([`playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md)).

A recurring product/engineering temptation is to **keep imported vibes “fresh”** when admins improve presets: push layer changes, fix volumes, swap sounds, or update visuals automatically. That implies **realtime or batch synchronization**, **subscriptions**, **version pins**, or **inheritance graphs** between catalog and user libraries.

Such systems introduce **remote mutation** of user data, **offline inconsistency** (snapshots vs live template), **playback indirection** (resolve preset at play time), and **backend jobs** (observers, webhooks, migration engines). Ixora **does not implement** any of these paths today and **explicitly rejects** realtime preset→vibe sync as architecture.

---

## Decision

**Ixora does not support realtime synchronization between presets and imported user vibes.**

### What is forbidden (architecture)

| Pattern | Status |
| --- | --- |
| **Realtime preset → vibe propagation** | **Not supported** — admin `PATCH` / `PUT …/sounds` on preset does **not** touch imported vibes |
| **Remote mutation of user vibes** from catalog changes | **Forbidden** — no server-side rewrite of user `vibe_sounds` tied to preset edits |
| **Preset observer / listener system** | **None** — no DB triggers, event subscribers, or queues watching `preset_vibes` for fan-out |
| **Subscription / sync model** | **None** — no “follow preset” flag, no WebSocket push, no FCM “refresh your vibe” |
| **Inheritance graph** | **None** — no parent preset id, no child vibe lineage |
| **Playback runtime coupling to preset catalog** | **Forbidden** — play, plan build, offline resolve use **`vibes/{id}`** only |
| **Partial sync** (layers only, metadata only) | **Not shipped** |
| **Version-based auto-update** of old imports | **Not shipped** |
| **Migration engine** to retarget imports when preset changes | **Not shipped** |

### What remains true (see ADR-003)

| Rule | Detail |
| --- | --- |
| **Imported vibes are independent** | No `preset_vibe_id` FK; copy-on-import transaction only |
| **Preset edits affect future imports only** | New **`POST …/import`** copies current template |
| **User may edit imported vibe freely** | Divergence is expected and allowed |
| **Re-import creates a new vibe** | Does not upgrade existing import in place |

### Runtime isolation

```
preset_vibes (catalog, admin-maintained)
       │
       │  one-time POST /import  ──►  vibes + vibe_sounds (user-owned)
       │
       ✕  no ongoing arrow
       ✕  no observer / queue / push

Playback path:
  GET /api/vibes/:id/sounds  →  buildVibeExecutionPlan  →  player.store
  (preset endpoints never consulted during play)
```

**Execution plan** input is always **`VibeSound[]`** from the **user vibe** or **offline snapshot** — never live preset layers ([`execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md)).

---

## Consequences

### Positive (motivations)

| Motivation | How no-sync delivers it |
| --- | --- |
| **Deterministic playback** | Layer config is whatever is on **`vibe_sounds`** (+ offline snapshot) at play time — no hidden template fetch |
| **Offline compatibility** | [`ADR-004`](ADR-004-offline-audio-strategy.md) snapshots keyed by **user `vibeId`** — no preset channel required offline |
| **User ownership clarity** | User library is **theirs** until they edit or delete — not administratively overwritten |
| **Simpler runtime architecture** | No preset resolver in `audio-player.service`, player store, or execution planner |
| **Simpler deletion semantics** | Delete preset or user vibe — no sync graph, no orphan subscription rows |
| **Reduced backend complexity** | No fan-out jobs, version tables, or conflict resolution on admin save |
| **No hidden state propagation** | Admin changes are **visible in catalog only** — users opt in via **new import** |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Imported vibes may become outdated** | Template improvements do not flow to existing My Vibes rows |
| **Preset fixes don’t reach old imports** | Users need **re-import** (new vibe) or manual layer edits to match template |
| **Duplicate vibes if user wants “latest preset”** | Re-import policy allows multiple copies — no in-place upgrade |
| **Support ambiguity** | “My import doesn’t match Presets tab” is **by design**, not a sync bug |

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Live-linked presets** | User vibe holds FK + runtime merge from preset — breaks offline and ownership expectations |
| **Partial synchronization** | e.g. sync sounds but not name — still remote mutation and conflict rules |
| **Version-based updates** | Pin import to preset `@ v3`, offer “Upgrade to v4” — requires version schema, diff, and user consent flows; **deferred** |
| **Migration engine** | Batch job retargets all imports when admin saves — hidden bulk mutation; high risk |
| **Realtime push (FCM/WebSocket)** | Notify app to refetch preset and patch vibe — still sync model; not implemented |
| **Play preset catalog directly** | Presets not playable; would bypass user **`vibes`** model |

If product later requires **optional** “update my import from preset” as an **explicit user action**, that requires a **new ADR**, feature spec, and consent UX — not incremental realtime sync.

---

## Relationship to other decisions

| ADR | Relationship |
| --- | --- |
| **[ADR-003](ADR-003-preset-import-independent-vibes.md)** | Establishes **copy-on-import** — foundation for this no-sync decision |
| **[ADR-004](ADR-004-offline-audio-strategy.md)** | Offline snapshots assume **stable user vibe state** without preset polling |
| **[`scheduling-model.md`](../architecture/backend/scheduling-model.md)** | Future automation also avoids mutating user vibes from catalog without explicit delivery spec |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`ADR-003-preset-import-independent-vibes.md`](ADR-003-preset-import-independent-vibes.md) | Import independence — complementary decision |
| [`../specs/preset-vibes/spec.md`](../specs/preset-vibes/spec.md) | “No preset version sync engine” — catalog out of scope |
| [`../specs/preset-vibes/import/spec.md`](../specs/preset-vibes/import/spec.md) | Explicit: no live sync after import |
| [`../specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) | Runtime isolated from preset catalog |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | Plan from user **`vibe_sounds`** only |
| [`../specs/vibes/offline-download/spec.md`](../specs/vibes/offline-download/spec.md) | No auto-refresh when preset changes |

### Evidence in codebase (absence of sync)

| Check | Expected |
| --- | --- |
| `vibes` schema | **No** `preset_vibe_id` column |
| `PresetVibeController::update` / `syncSounds` | Mutates **`preset_*`** only — **no** user vibe writes |
| Background jobs for preset fan-out | **None** |
| Mobile preset listeners at playback | **None** |

---

**Reminder:** Realtime or batch preset→vibe synchronization is **intentionally absent**. Admin catalog changes and user libraries evolve **independently** unless the user imports again or edits their vibe explicitly.
