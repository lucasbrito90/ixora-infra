# ADR-003: Preset import creates independent user-owned vibes

## Status

**Accepted** — reflects the **current shipped architecture** in `PresetVibeController::import` and mobile import flow.

## Date

2026-05-23

## Context

Ixora exposes **preset vibes** — admin-curated catalog templates (`preset_vibes`, `preset_vibe_sounds`) — that mobile users **browse** and **import** into **My Vibes**. Presets are **not playable** directly; playback, offline download, layer editing, and ownership policies all target **user-owned `vibes`**.

A design fork existed: treat imported vibes as **live views** of a preset (sync when admin edits the template) versus **one-time copies** that become ordinary user vibes. Live binding would require sync engines, version pins, inheritance chains, and runtime indirection — complicating **offline snapshots**, **deletion**, and **predictable playback** ([`playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md), [`offline-download/spec.md`](../specs/vibes/offline-download/spec.md)).

The product chose **copy-on-import**: transactional duplication of metadata and pivot configuration into new rows owned by the importing user, with **no persistent link** back to the preset.

---

## Decision

**Importing a preset creates a fully independent user-owned vibe.**

### What import creates (one transaction)

| Artifact | Behaviour |
| --- | --- |
| **`vibes` row** | **New `INSERT`** — `user_id` = authenticated user; **`name`**, **`description`** copied from preset |
| **Visual URLs** | **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** copied as **HTTPS strings** from preset’s optional **`cover_bundle`** — **no `cover_bundle_id` FK** on user vibe |
| **`vibe_sounds` rows** | **New pivot attaches** — one per **`preset_vibe_sounds`** row (volume, `play_mode`, timing fields, etc.) |
| **Catalog `sounds`** | **Not duplicated** — pivot references **existing** catalog **`sound_id`** / **`file_url`** |

### What import does **not** create

| Pattern | Status |
| --- | --- |
| **`preset_vibe_id`** (or any live FK) on **`vibes`** | **Absent** — no binding column |
| **Preset inheritance chain** | **None** |
| **Background sync job** | **None** |
| **Ongoing synchronization** | **None** — admin preset edits affect **future imports only** |
| **Hidden remote mutation** of imported vibes | **Forbidden by architecture** |

### Independence rules (authoritative)

| Rule | Detail |
| --- | --- |
| **Own ownership** | Imported vibe has **`user_id`**; **`VibePolicy`** applies like manual create |
| **Free divergence** | User may PATCH vibe metadata, attach/detach/configure layers — preset unchanged |
| **Preset changes** | Do **not** mutate previously imported vibes |
| **Re-import** | Each import creates **another** vibe — duplicates allowed |
| **Delete preset** | Does **not** cascade to imported vibes (no FK link) |
| **Delete imported vibe** | Standard user vibe delete — no preset side effects |
| **Playback / runtime** | **`GET /api/vibes/{id}/sounds`**, **`buildVibeExecutionPlan`**, offline snapshot — all use **imported vibe id only**; preset endpoints **not** involved at play time |
| **Offline** | User must **Download for offline** on the **imported vibe** — import does **not** auto-cache; snapshot stores **`vibeSounds[]`** for that vibe id |

### Catalog vs user composition (unchanged)

```
preset_vibes ── preset_vibe_sounds ──► sounds (catalog)
       │
       │  POST /import  (one-time copy)
       ▼
vibes (user-owned) ── vibe_sounds ──► sounds (same catalog rows)
       NO preset_vibe_id
       NO live sync
```

---

## Consequences

### Positive (motivations)

| Motivation | How independence delivers it |
| --- | --- |
| **Offline compatibility** | Offline manifest keyed by **user `vibeId`** + stable **`vibeSounds[]`** — no preset fetch at play time |
| **Predictable playback** | Same execution-plan and player stack as manual vibes — no template indirection |
| **User ownership** | Clear **`user_id`** scope for list, edit, delete, policies |
| **Simpler runtime** | Mobile never resolves “preset vs vibe” at playback — always **`vibes/{id}`** |
| **Simpler deletion semantics** | Delete vibe / sound attach rules unchanged; no sync graph |
| **No cascading preset updates** | Admin can revise catalog without rewriting user libraries |
| **No hidden remote mutations** | User’s saved vibe stays as last written until **they** or **explicit API** changes it |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Duplicated metadata** | Name, description, visual URL strings copied per import — storage in PostgreSQL, not deduplicated by preset |
| **Duplicated `vibe_sounds` rows** | Each import creates full pivot set — more rows than a shared reference model |
| **Stale copies** | User’s vibe may diverge from **current** preset template; re-import required for a fresh template snapshot |
| **Shared CDN URLs** | Copied visual URLs may point at same bundle objects as catalog — deletion policy must respect URL reference rules ([`storage-strategy.md`](../architecture/storage/storage-strategy.md)) |
| **No “update all imports”** | Admin cannot push template fixes to existing user vibes without a **future explicit product** (not planned) |

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Live preset references** | Imported vibe would depend on preset row + sync; breaks offline-first playback and clear ownership |
| **Inheritance trees** | Parent/child vibe graph, merge rules, and delete propagation — high complexity |
| **Sync engine** | Background jobs to propagate `preset_vibe_sounds` changes to linked user vibes — **explicitly out of scope** in import spec |
| **Version pinning** | User vibe pinned to `preset_vibe @ version N` — still needs sync, migration, and runtime resolution; deferred |
| **Play preset directly** | Presets are catalog-only; playback requires user **`vibes`** row |
| **Duplicate catalog `sounds` on import** | Would bloat catalog and break shared **`file_url`**; rejected — only **pivot** rows duplicate |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/preset-vibes/spec.md`](../specs/preset-vibes/spec.md) | Catalog domain — presets not user-owned; import is separate flow |
| [`../specs/preset-vibes/import/spec.md`](../specs/preset-vibes/import/spec.md) | **Feature spec** — transaction, fields copied, API contract |
| [`../specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) | Playback consumes **`vibe_sounds`** on user vibe — no preset binding |
| [`../specs/vibes/offline-download/spec.md`](../specs/vibes/offline-download/spec.md) | Offline snapshot per **imported `vibeId`** — not preset id |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | Plan built from imported vibe’s layers |
| [`../architecture/storage/storage-strategy.md`](../architecture/storage/storage-strategy.md) | Copied URL strings vs bundle-owned objects |
| [`../decisions/ADR-002-laravel-only-storage-writes.md`](ADR-002-laravel-only-storage-writes.md) | Import copies URLs only — no Spaces writes |

### Implementation reference (current)

| Artifact | Path |
| --- | --- |
| Import route | `POST /api/preset-vibes/{preset_vibe}/import` — `back_vibes/routes/api.php` |
| Import action | `back_vibes/app/Http/Controllers/Api/PresetVibeController.php` — **`import()`** |
| Feature tests | `back_vibes/tests/Feature/PresetVibeImportApiTest.php` |
| Mobile | `front_vibes` — `PresetVibeDetailPage`, `preset-vibe.service.ts` (`importPresetVibe`) |

---

If product later requires **live preset sync** or **version pinning**, supersede this ADR with a new numbered decision and a dedicated feature spec — do not incrementally add hidden FKs or background sync without that review.
