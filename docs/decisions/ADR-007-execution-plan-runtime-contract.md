# ADR-007: Execution plan as mobile playback runtime contract

## Status

**Accepted** — reflects **current shipped architecture** in `front_vibes` (`player-engine.service.ts`, `player.store`, `audio-player.service`).

## Date

2026-05-23

## Context

Ixora mobile plays multi-layer vibes from **`vibe_sounds`** pivot data plus catalog **`file_url`** fields returned by Laravel. The API shape (`VibeSound`, pivot aliases, nullable timing fields, legacy **`loop`** flag) is optimized for **persistence and CRUD**, not for **native scheduling** (offsets, interval gaps, playability rules, offline URL identity).

The player stack needs a **stable, deterministic intermediate representation** between:

- **Backend read model** — `GET /api/vibes/{id}/sounds` or offline snapshot **`vibeSounds[]`**
- **Playback runtime** — Pinia **`playVibe`**, **`audioPlayerService.playPlan`**, NativeAudio / HTML fallback

Without that boundary, schedulers would scatter pivot parsing across UI and audio services, break **offline rebuild**, and invite **non-deterministic** behaviour (shuffle, server-side graphs, raw JSON passed to ExoPlayer).

The team adopted **`buildVibeExecutionPlan`** → **`VibeExecutionLayer[]`** as the **canonical runtime contract**. Laravel **does not** build or execute plans today ([`scheduling-model.md`](../architecture/backend/scheduling-model.md)).

---

## Decision

**The execution plan is the canonical runtime contract between backend vibe data and mobile playback runtime.**

### Authoritative transformation

| Layer | Role |
| --- | --- |
| **Input** | **`VibeSound[]`** — from API **`normalizeVibeSoundFromApi`** or **`offline_vibe_manifest_v1`** snapshot |
| **Transformer** | **`buildVibeExecutionPlan(vibeSounds)`** in **`player-engine.service.ts`** — **pure**, deterministic |
| **Output** | **`VibeExecutionLayer[]`** — **only** shape consumed by **`playVibe`**, **`playPlan`**, offline download, URL resolve |

**Rule:** Playback code **must not** schedule layers directly from raw API responses or ad hoc pivot field reads.

### What the plan owns (runtime semantics)

| Concern | Plan field / rule |
| --- | --- |
| **Layer ordering** | Sort by **`sort_order`** → **`sortOrder`** |
| **`play_mode`** | **`playMode`**: `loop` \| `once` \| `interval` — pivot **`loop`** flag not used by planner |
| **Start delay** | **`start_offset_seconds`** → **`startsAtSeconds`** |
| **Wall-clock cap** | **`play_duration_seconds`** → **`durationSeconds`** / **`endsAtSeconds`** |
| **Interval gap** | **`repeat_interval_seconds`** → **`repeatIntervalSeconds`** (interval mode only) |
| **Audio URL** | Catalog **`file_url`** → **`fileUrl`** — pivot does not override source |
| **URL resolution key** | **`fileUrl`** + **`soundId`** for offline manifest match ([`ADR-004`](ADR-004-offline-audio-strategy.md)) |
| **Playability** | **`isExecutionLayerPlayable`** / **`countValidLayers`** before **`playPlan`** |
| **Playback lifecycle input** | Full plan passed to **`audioPlayerService.playPlan(layers)`** — timers/modes read plan fields only |

Fade pivot fields are **copied** into the plan but **ignored** at runtime — documented in execution-plan spec, not applied by scheduler.

### Runtime data flow (mandatory)

```
VibeSound[]  (API or offline snapshot)
       │
       ▼
buildVibeExecutionPlan()     ← authoritative; no backend equivalent
       │
       ▼
VibeExecutionLayer[]         ← canonical contract
       │
       ├── player.store.playVibe({ layers })
       ├── audioPlayerService.playPlan(layers)
       ├── audioEngine.resolvePlaybackAssetUrl(layer, vibeId)
       └── cacheVibeAudio(vibeId, layers)   [offline download]
```

### Offline compatibility

- Snapshots persist **`vibeSounds[]`** in **`VibeSound` API shape** — **not** pre-built plans.
- On hydrate: same **`buildVibeExecutionPlan(snapshot.vibeSounds)`** as online.
- **Plan inputs** stay compatible; **URL resolution** may differ (`file://` vs HTTPS).

### Explicit non-goals (today)

| Pattern | Status |
| --- | --- |
| **Backend scheduler / execution engine** | **None** — Laravel stores pivot; mobile interprets |
| **Backend-generated playback graphs** | **None** |
| **Direct playback from raw `VibeSound[]`** | **Forbidden** in player path |
| **Hidden runtime randomization** | **None** — no shuffle in planner or **`playPlan`** |
| **Dynamic runtime evaluation** of pivot without plan rebuild | **Forbidden** — rebuild plan when **`vibeSounds`** change |

### Future compatibility (planning only)

When **[`scheduling-model.md`](../architecture/backend/scheduling-model.md)** or push automation ships, the intended boundary remains: **trigger** may arrive from backend/mobile automation, but **playback still runs `buildVibeExecutionPlan` → `playVibe`** on the **user vibe’s** layer rows — not a server-side audio engine or live preset graph ([`ADR-005`](ADR-005-no-realtime-preset-sync.md)).

---

## Consequences

### Positive (motivations)

| Motivation | How the execution plan delivers it |
| --- | --- |
| **Deterministic playback** | Same **`VibeSound[]`** → same **`VibeExecutionLayer[]`**; no randomness |
| **Stable offline behaviour** | Snapshot stores plan **inputs**; one code path rebuilds plan offline |
| **Runtime isolation** | API/pivot evolution contained in **`player-engine.service`** + normalizer |
| **Simpler player architecture** | **`audio-player.service`** schedules **`VibeExecutionLayer`** only |
| **Future scheduler compatibility** | Automation fires **`playVibe`** with same plan contract — no parallel graph format |
| **Future automation compatibility** | Server dispatch ≠ server mixing; plan remains client interpretation of **`vibe_sounds`** |

### Negative (tradeoffs)

| Tradeoff | Impact |
| --- | --- |
| **Duplicated transformation layer** | Mapping logic lives in mobile planner — must stay aligned with API pivot semantics |
| **Execution-plan maintenance burden** | New pivot fields require planner + spec + tests before runtime use |
| **Runtime compatibility expectations** | Consumers assume stable **`VibeExecutionLayer`** shape — breaking changes need coordinated release |
| **No server-side validation of plan** | Invalid interval/layer combos filtered at play time on device |
| **Two representations in memory** | **`vibeSounds`** for UI/edit; **`executionPlan`** for play — must rebuild on change |

---

## Alternatives Considered

| Alternative | Why not chosen (for Ixora today) |
| --- | --- |
| **Direct raw API playback** | Scatters pivot rules; breaks offline snapshot parity; couples NativeAudio to **`VibeSoundResource`** |
| **Backend-generated playback graphs** | Requires server execution engine, streaming auth, and duplicate scheduling logic — **none shipped** |
| **Fully dynamic runtime evaluation** | Re-parse pivot on every tick — harder to test, non-deterministic risk, no single contract |
| **Persist pre-built plan in offline snapshot** | API shape change would stale stored plans; storing **`vibeSounds[]`** + rebuild is simpler |
| **Preset catalog at play time** | Rejected — playback uses user **`vibes`** only ([`ADR-003`](ADR-003-preset-import-independent-vibes.md)) |

---

## Relationship to other decisions

| ADR / doc | Relationship |
| --- | --- |
| **[ADR-004](ADR-004-offline-audio-strategy.md)** | Offline download + resolve keyed on **`layer.fileUrl`** from plan |
| **[ADR-003](ADR-003-preset-import-independent-vibes.md)** | Imported vibes feed same plan path as manual vibes |
| **[ADR-005](ADR-005-no-realtime-preset-sync.md)** | No preset indirection at plan build time |
| **[`scheduling-model.md`](../architecture/backend/scheduling-model.md)** | Future automation must not replace plan — only trigger it |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | **Field-level spec** — mapping rules, interval semantics, playability |
| [`../specs/vibes/playback-runtime/spec.md`](../specs/vibes/playback-runtime/spec.md) | Player store, audio service, prepare handshake |
| [`../architecture/audio/playback-runtime.md`](../architecture/audio/playback-runtime.md) | Architecture — state machine, NativeAudio boundaries |
| [`../specs/vibes/offline-download/spec.md`](../specs/vibes/offline-download/spec.md) | Snapshot stores plan inputs; download uses plan layers |
| [`../specs/vibes/manage-vibe-sounds/spec.md`](../specs/vibes/manage-vibe-sounds/spec.md) | Pivot fields that feed **`VibeSound[]`** input |

### Implementation reference (current)

| Artifact | Path |
| --- | --- |
| Planner | `front_vibes/src/services/player-engine.service.ts` |
| Composable | `front_vibes/src/composables/usePlayerEngine.ts` |
| Input type | `front_vibes/src/services/vibe-sound.service.ts` |
| Store handoff | `front_vibes/src/stores/player.store.ts` — **`playVibe({ layers })`** |
| Scheduler | `front_vibes/src/services/audio-player.service.ts` — **`playPlan(layers)`** |
| Offline snapshot | `front_vibes/src/services/offline-vibe-cache.service.ts` |
| API source | `back_vibes/app/Http/Resources/VibeSoundResource.php` |

### Consumer rules (review checklist)

- [ ] **`audio-player.service`** reads **`VibeExecutionLayer`** fields — not raw **`VibeSound`**
- [ ] **`VibePlayerPage`** calls **`buildPlan`** before **`playVibe`**
- [ ] Offline hydrate → **`buildPlan`** before play
- [ ] No new shuffle/random order in planner without ADR supersession
- [ ] Backend does not add “play graph” endpoints without new ADR

---

When the runtime contract changes (new layer fields, backend plan generation, or preset indirection), supersede this ADR and update [`execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) in the same change set.
