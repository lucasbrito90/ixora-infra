# Execution Plan — internal runtime contract (mobile)

**Status:** Active feature specification (source of truth)  
**Version:** 1.0 (matches current `front_vibes` `player-engine.service.ts` + consumers)  
**Feature ID:** `vibes/execution-plan`  
**Platform:** Mobile (`front_vibes`); **no** backend execution engine

---

## Goal

Document the **execution plan** as the **internal runtime contract** between:

- **`vibe_sounds` API data** (`VibeSound[]`)
- **`buildVibeExecutionPlan`** (`player-engine.service.ts`)
- **`player.store`** (Pinia)
- **`audio-player.service`** (multi-layer scheduler)
- **Offline snapshots** (`offline_vibe_manifest_v1`)

The plan is a **pure, client-side interpretation** of pivot configuration into ordered **`VibeExecutionLayer[]`**. It does **not** load audio, schedule server jobs, or apply fades.

**Success criteria:**

- Same **`VibeSound[]` input** always yields the same **`VibeExecutionLayer[]`** (deterministic).
- **`fileUrl`** on each layer is the catalog **`sounds.file_url`** exposed as **`VibeSound.file_url`** — never a pivot override.
- Offline playback resolves only when manifest **`remoteUrl`** **exactly equals** **`layer.fileUrl.trim()`**.
- **`fade_in_seconds` / `fade_out_seconds`** are copied into the plan but **ignored** by the runtime.
- **No backend** endpoint builds or executes plans; Laravel only stores pivot + returns read JSON.
- **No randomization** in plan generation or layer ordering (none implemented today).

---

## Scope

### In scope

- **`VibeExecutionLayer`** shape and field semantics
- **`buildVibeExecutionPlan`** mapping rules (`VibeSound` → layer)
- Layer **ordering** (`sort_order`)
- **`play_mode`** mapping (`loop` | `once` | `interval`)
- **Interval timing** (`repeat_interval_seconds` vs `play_duration_seconds`)
- **`start_offset_seconds`**, **`play_duration_seconds`**, derived **`endsAtSeconds`**
- **`fileUrl`** provenance and offline **URL identity**
- **Playability** helpers (`hasValidExecutionFileUrl`, `isExecutionLayerPlayable`)
- **Lifecycle:** API load, offline snapshot hydrate, **`usePlayerEngine`**, **`playVibe` → `playPlan`**
- **Determinism** and explicit **non-goals**

### Out of scope

- **Backend execution engine**, cron, or server-side playback scheduler — **does not exist**
- **Automation** that starts/stops vibes on a timetable — **not implemented**
- **Runtime fade-in / fade-out** — stored on pivot/plan, **not applied** ([`audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md))
- **`tick_duration_seconds`** — documented as future idea in code comments only; **not in API or plan today**
- **NativeAudio / ExoPlayer** internals — see [`../playback-runtime/spec.md`](../playback-runtime/spec.md)
- **Download for offline** pipeline — see [`../offline-download/spec.md`](../offline-download/spec.md)
- **Managing layers** (attach/PATCH) — see [`../manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md)

---

## Actors

| Actor | Role |
| --- | --- |
| **Laravel API** | Returns **`VibeSoundResource`** rows from **`GET /api/vibes/{id}/sounds`** — pivot + catalog fields. Does **not** build execution plans. |
| **`vibe-sound.service`** | Fetches sounds; **`normalizeVibeSoundFromApi`** ensures canonical **`file_url`**. |
| **`player-engine.service`** | Pure **`buildVibeExecutionPlan`**, URL/playability helpers. |
| **`usePlayerEngine`** | Module-level **`executionPlan`** ref; **`buildPlan` / `clearPlan`**. |
| **`VibePlayerPage`** | Loads sounds (API or snapshot) → **`buildPlan`** → passes plan to store. |
| **`player.store`** | **`playVibe({ layers })`** → validates count → **`audioPlayerService.playPlan`**. |
| **`audio-player.service`** | Schedules layers by **`playMode`**, offsets, duration caps, interval gaps. |
| **`audioEngine`** | **`resolvePlaybackAssetUrl(layer, vibeId)`** — offline **`file://`** when URL matches manifest. |
| **Offline snapshot** | Stores **`vibeSounds[]`** copy for plan rebuild when API is unreachable. |

---

## Runtime contract (data flow)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  INPUT: VibeSound[]                                                     │
│  • GET /api/vibes/:id/sounds  (online)                                  │
│  • OfflineVibeSnapshot.vibeSounds  (offline_vibe_manifest_v1)           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
              buildVibeExecutionPlan(vibeSounds)   ← pure function
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  PLAN: VibeExecutionLayer[]  (usePlayerEngine.executionPlan)          │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
              player.store.playVibe({ vibeId, layers, … })
                                │
                                ▼
              audioPlayerService.playPlan(layers)
                                │
              per layer: resolvePlaybackAssetUrl(layer, vibeId)
                    • offline: manifest.remoteUrl === layer.fileUrl.trim()
                    • else: layer.fileUrl (HTTPS CDN)
```

**There is no server-side plan builder.** The backend persists **`vibe_sounds`** pivot columns and catalog **`file_url`**; the mobile app is the sole interpreter at playback time.

---

## Input: `VibeSound[]`

Normalized type in **`front_vibes/src/services/vibe-sound.service.ts`**. Source: **`VibeSoundResource`** (`back_vibes`).

| Field | Origin | Used by planner |
| --- | --- | --- |
| `id` | Catalog **`sounds.id`** | → **`soundId`** |
| `name` | Catalog | → **`soundName`** |
| **`file_url`** | Catalog **`sounds.file_url`** (HTTPS CDN) | → **`fileUrl`** |
| `volume` | Pivot | → **`volume`** |
| `sort_order` | Pivot | Sort key → **`sortOrder`** |
| **`play_mode`** | Pivot (`loop` \| `once` \| `interval`) | → **`playMode`** |
| **`start_offset_seconds`** | Pivot (nullable) | → **`startsAtSeconds`** (default 0) |
| **`play_duration_seconds`** | Pivot (nullable) | → **`durationSeconds`**; drives **`endsAtSeconds`** |
| **`repeat_interval_seconds`** | Pivot (nullable) | → **`repeatIntervalSeconds`** (interval only) |
| **`fade_in_seconds`** | Pivot (nullable) | → **`fadeInSeconds`** (default 0) — **not applied at runtime** |
| **`fade_out_seconds`** | Pivot (nullable) | → **`fadeOutSeconds`** (default 0) — **not applied at runtime** |
| `loop` | Pivot (derived server-side) | **Not read** by **`buildVibeExecutionPlan`** — **`play_mode`** is source of truth |
| `thumbnail_url`, `category`, `duration` | Catalog | UI / catalog only — **not** copied to execution layer |

### `file_url` normalization

Before planning, **`normalizeVibeSoundFromApi`** sets **`file_url`** from the API row:

1. Trim **`file_url`** if non-empty string → use as canonical URL.
2. Else trim legacy **`audio_url`** if present (backward compatibility).
3. Else **`''`**.

The planner assigns **`fileUrl: vs.file_url`** without re-trimming in the map step; consumers trim at validation/resolution time.

---

## Output: `VibeExecutionLayer`

Defined in **`player-engine.service.ts`**.

```typescript
interface VibeExecutionLayer {
  soundId: number;              // VibeSound.id (catalog sound id)
  soundName: string;
  fileUrl: string;              // VibeSound.file_url — catalog CDN URL
  volume: number;                 // 0–100
  playMode: 'loop' | 'once' | 'interval';

  startsAtSeconds: number;        // start_offset_seconds ?? 0
  endsAtSeconds: number | null; // startsAt + duration when duration set
  durationSeconds: number | null; // play_duration_seconds ?? null

  repeatIntervalSeconds: number | null; // interval mode only; else null

  fadeInSeconds: number;          // stored; runtime ignores
  fadeOutSeconds: number;         // stored; runtime ignores

  sortOrder: number;
  humanReadableSummary: string; // display-only one-liner
}
```

### Field semantics

| Field | Meaning |
| --- | --- |
| **`soundId`** | Catalog sound primary key. Used as native asset key (`vibe-layer-{soundId}`) and offline manifest key (`vibeId:soundId`). **Not** a pivot row id. |
| **`fileUrl`** | **Exact** playback URL string from catalog **`file_url`**. Pivot does not override audio source. |
| **`startsAtSeconds`** | Delay from **vibe session start** before this layer begins preload/play. |
| **`durationSeconds`** | Wall-clock cap for the layer **from when it actually starts** (after offset). `null` = run until user stops the vibe. |
| **`endsAtSeconds`** | **Derived** absolute second on the vibe timeline: `startsAtSeconds + durationSeconds` when duration is set; else `null`. Informational for UI; runtime schedules stop via **`durationSeconds`** from layer start. |
| **`repeatIntervalSeconds`** | **Only** when **`playMode === 'interval'`**. Silence gap **after** each tick **ends**, before the next tick. `null` for `loop` and `once`. |
| **`fadeInSeconds` / `fadeOutSeconds`** | Copied from pivot for completeness and future use. **`audio-player.service` does not apply them.** |
| **`humanReadableSummary`** | Built from name, mode, offset, duration, volume — dev/UI only. |

---

## `buildVibeExecutionPlan` rules

**Location:** **`front_vibes/src/services/player-engine.service.ts`**

**Pure function** aside from **DEV-only** `[CDNAssets]` hostname logs.

### Algorithm

1. **Copy** input array (does not mutate caller’s array).
2. **Sort** ascending by **`sort_order`** (layer ordering for plan list and parallel registration order).
3. **Map** each **`VibeSound`** to **`VibeExecutionLayer`**:

```typescript
startsAtSeconds  = start_offset_seconds ?? 0
durationSeconds  = play_duration_seconds ?? null
endsAtSeconds    = durationSeconds != null ? startsAtSeconds + durationSeconds : null

repeatIntervalSeconds =
  play_mode === 'interval'
    ? (repeat_interval_seconds ?? null)
    : null

fadeInSeconds    = fade_in_seconds ?? 0
fadeOutSeconds   = fade_out_seconds ?? 0

fileUrl          = file_url   // as normalized on VibeSound
soundId          = id
playMode         = play_mode
```

4. Attach **`humanReadableSummary`** via **`buildSummary`**.
5. Return ordered array.

### Determinism

| Property | Guarantee |
| --- | --- |
| Same input rows | Same output layers (field-wise), regardless of input array order |
| Sort stability | Tie on **`sort_order`** preserves relative order from sort implementation |
| No randomness | No shuffle, random pick, or jitter — **not implemented anywhere in the planner** |
| No time dependency | Plan does not embed `Date.now()` or session ids |
| No network | Planner never fetches URLs or validates reachability |

### What the planner does **not** do

- Does **not** filter out invalid URLs (filtering is **`isExecutionLayerPlayable`** / **`countValidLayers`** at play time).
- Does **not** deduplicate sounds (same **`soundId`** twice → two layers if API returns two rows — unlikely due to DB unique constraint).
- Does **not** merge layers or build a timeline DAG.
- Does **not** call the backend.

---

## Layer ordering

| Rule | Detail |
| --- | --- |
| Sort key | **`sort_order`** ascending |
| Plan index | Lower **`sort_order`** appears first in **`VibeExecutionLayer[]`** |
| Playback registration | **`playPlan`** iterates plan in array order; all layers are registered, then each respects its own **`startsAtSeconds`** |
| Concurrent layers | Multiple layers may be active simultaneously — order does not imply exclusivity |
| User-visible list | **`VibePlayerPage`** / **`VibeSoundsPage`** DEV panels show plan in sort order |

**No random layer order.** Order is entirely data-driven from pivot **`sort_order`**.

---

## `play_mode` mapping

| API `play_mode` | Plan `playMode` | Runtime behaviour (summary) |
| --- | --- | --- |
| **`loop`** | `'loop'` | Native **`NativeAudio.loop`** (or HTML fallback) until stop or duration cap |
| **`once`** | `'once'` | Single play; layer torn down on **`complete` / `ended`** |
| **`interval`** | `'interval'` | Preload once; repeated **`play`** ticks with gap **`repeatIntervalSeconds`** |

**`loop` boolean on `VibeSound`:** Server derives **`loop = (play_mode === 'loop')`**. The execution planner reads **`play_mode` only** — not the legacy **`loop`** flag.

Default when pivot omits mode (API): **`loop`** (`VibeSoundResource` default).

---

## Timing fields

### `start_offset_seconds` → `startsAtSeconds`

| Value | Behaviour |
| --- | --- |
| `null` / omitted | **`0`** — layer starts immediately when **`playPlan`** runs |
| `n > 0` | **`audio-player.service`** waits **`n` seconds** (`setTimeout`) before preload/play for that layer |

Offset is measured from **vibe session start** (when **`playPlan`** is invoked), not from other layers finishing.

### `play_duration_seconds` → `durationSeconds` / `endsAtSeconds`

| Value | Planner | Runtime |
| --- | --- | --- |
| `null` | **`durationSeconds: null`**, **`endsAtSeconds: null`** | Layer runs until user stops vibe (subject to mode) |
| `n > 0` | **`durationSeconds: n`**, **`endsAtSeconds: startsAt + n`** | Hard **`stopLayer`** after **`n` seconds** from **layer start** (after offset). **No fade-out.** |

**Important:** The duration timer starts when the layer **begins** (after **`startsAtSeconds`** delay), not at vibe t=0. For offset `10` and duration `60`, the layer stops at vibe timeline **~70s**, matching derived **`endsAtSeconds`**.

### Interval mode — `repeat_interval_seconds`

**Only preserved when `play_mode === 'interval'`.** For `loop` / `once`, planner sets **`repeatIntervalSeconds: null`** even if pivot stored a value.

| Concept | Semantics |
| --- | --- |
| **Tick** | One **`play`** of the audio asset (length = **file natural duration**) |
| **`repeat_interval_seconds`** | **Silence gap after tick END**, before next tick **starts** — **not** a fixed period including play time |
| **`play_duration_seconds`** | Total wall-clock time the **interval layer stays active** from its start (after offset); all ticks must fit within this window. `null` = repeat until user stops |

**Example:**

```
repeat_interval_seconds = 30
play_duration_seconds   = 300
startsAtSeconds         = 0

→ play file (e.g. 45s natural length) → silence 30s → play again → … → hard stop at ~300s layer lifetime
```

**Not:** “play 30s then wait 30s” unless the file itself is 30s long.

**Playability:** Interval layers require **`repeatIntervalSeconds >= 1`**. Missing or `< 1` → **`isExecutionLayerPlayable`** false → skipped at play (logged).

**Not implemented:** **`tick_duration_seconds`** (force-stop each tick early). Mentioned in code comments only — **must not** be documented as current behaviour.

---

## `fileUrl` and offline URL identity

### Provenance

| Stage | URL |
| --- | --- |
| Storage | **`sounds.file_url`** on catalog row (Laravel / Spaces CDN) |
| API | **`VibeSoundResource.file_url`** |
| Client normalize | **`VibeSound.file_url`** |
| Execution plan | **`VibeExecutionLayer.fileUrl`** (= **`vs.file_url`**) |

Pivot columns do **not** supply an alternate audio URL.

### Validation (`hasValidExecutionFileUrl`)

Non-empty trimmed string that parses as URL (absolute or relative-with-base fallback). Empty → not playable.

### Offline resolution (exact match)

When **`audioEngine.resolvePlaybackAssetUrl(layer, vibeId)`** runs:

1. Look up **`ixora_offline_audio_manifest_v1`** entry for key **`{vibeId}:{soundId}`**.
2. Compare **`entry.remoteUrl === layer.fileUrl.trim()`** — **string equality**, no normalization beyond **trim**.
3. If match **and** file exists on disk → return **`file://`** URI via **`Filesystem.getUri`**.
4. Else → return **`layer.fileUrl`** (remote HTTPS).

| Requirement | Reason |
| --- | --- |
| Exact match | CDN path change, query string change, or trailing space mismatch → fallback to remote (offline file not used) |
| **`soundId`** + URL pair | Manifest is keyed by vibe + catalog sound id; URL must still match stored **`remoteUrl`** |

Offline **metadata snapshot** (`offline_vibe_manifest_v1`) stores the same **`VibeSound[]`** used to build the plan. On hydrate, **`buildVibeExecutionPlan(snapshot.vibeSounds)`** produces the **same plan shape** as online — only URL **resolution** may differ (local file vs CDN).

See [`../offline-download/spec.md`](../offline-download/spec.md).

---

## Fade fields — stored, ignored

| Field | In plan | At runtime |
| --- | --- | --- |
| **`fade_in_seconds`** | **`fadeInSeconds`** (default 0) | **Not applied** |
| **`fade_out_seconds`** | **`fadeOutSeconds`** (default 0) | **Not applied** |

Pivot and plan may carry fade values for future engine work or admin UX. **`audio-player.service`** explicitly documents fade removal; duration stops are hard **`stopLayer`** with no volume ramp.

---

## Playability and store handoff

### Helpers

| Function | Purpose |
| --- | --- |
| **`hasValidExecutionFileUrl(fileUrl)`** | URL non-empty and parseable |
| **`isExecutionLayerPlayable(layer)`** | Valid URL + interval gap ≥ 1 when mode is interval |
| **`audioPlayerService.countValidLayers(layers)`** | Count passing same rules |

### `player.store.playVibe`

1. **`countValidLayers(layers) === 0`** → abort, return `false`.
2. Set vibe context, **`playbackState: preparing`**.
3. **`audioPlayerService.playPlan(layers)`** — passes **full** plan; invalid layers skipped inside **`playLayer`**.

Plan array may include non-playable layers (bad URL, bad interval); they appear in UI/DEV but do not register native assets.

---

## Lifecycle

| Event | Action |
| --- | --- |
| **`VibePlayerPage` mount** | Fetch vibe + sounds (parallel) **or** **`getOfflineVibeSnapshot`** if API returns no sounds |
| Sounds available | **`buildPlan(vibeSounds)`** → **`executionPlan`** |
| User taps Play | **`store.playVibe({ layers: executionPlan, … })`** |
| Manage sounds save | Refetch sounds → **`buildPlan`** (shared **`usePlayerEngine`** ref) |
| Leave player / clear | **`clearPlan()`** optional; MiniPlayer session may keep store context |
| Successful offline download | **`saveOfflineVibeSnapshot(vibeId, vibe, vibeSounds)`** — snapshot for future plan rebuild |

**Composable:** **`usePlayerEngine`** — module-level **`executionPlan`** ref so player and sounds pages share one plan instance.

---

## Functional requirements

| ID | Requirement |
| --- | --- |
| EP-1 | **`buildVibeExecutionPlan`** is **pure** (deterministic output for given **`VibeSound[]`**). |
| EP-2 | Layers sorted by **`sort_order`** ascending before mapping. |
| EP-3 | **`fileUrl`** comes from **`VibeSound.file_url`** only (catalog CDN). |
| EP-4 | **`play_mode`** maps 1:1 to **`playMode`**; **`loop` pivot flag is not used** in planning. |
| EP-5 | **`repeatIntervalSeconds`** set only when **`play_mode === 'interval'`**. |
| EP-6 | **`startsAtSeconds`** defaults to **0** when pivot null. |
| EP-7 | **`endsAtSeconds`** computed as **`startsAt + duration`** when duration present. |
| EP-8 | Fade fields copied with default **0**; **runtime must not apply them**. |
| EP-9 | Offline playback uses **`remoteUrl === layer.fileUrl.trim()`** exact equality. |
| EP-10 | **No backend** plan generation or execution endpoint. |
| EP-11 | **No randomization** in plan order or layer selection. |

---

## Non-goals (explicit)

| Non-goal | Status |
| --- | --- |
| Server-side execution engine | **Does not exist** |
| Scheduled / automated vibe playback | **Not implemented** — do not infer from pivot fields |
| Runtime fades | **Ignored** |
| Seamless loop / crossfade | **Not promised** — see playback-runtime spec |
| **`tick_duration_seconds`** | **Not in schema** — comments only |
| Random layer order or sound pick | **Not implemented** |

---

## Related docs

| Doc | Relationship |
| --- | --- |
| [`../playback-runtime/spec.md`](../playback-runtime/spec.md) | End-to-end playback — engine, store, background, MiniPlayer |
| [`../manage-vibe-sounds/spec.md`](../manage-vibe-sounds/spec.md) | Pivot fields written by API; feeds **`VibeSound[]`** input |
| [`../offline-download/spec.md`](../offline-download/spec.md) | Audio bytes + metadata snapshot; URL match rules |
| [`../../../architecture/audio/audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md) | Why fades are stored but not applied |
| [`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md) | Catalog **`file_url`** origin |

---

## Implementation map

| Artifact | Path |
| --- | --- |
| Planner + types | `front_vibes/src/services/player-engine.service.ts` |
| Composable | `front_vibes/src/composables/usePlayerEngine.ts` |
| API client + `VibeSound` | `front_vibes/src/services/vibe-sound.service.ts` |
| URL normalize | `front_vibes/src/utils/sound-file-url.ts` |
| Store | `front_vibes/src/stores/player.store.ts` |
| Scheduler | `front_vibes/src/services/audio-player.service.ts` |
| Offline URL resolve | `front_vibes/src/services/audio-engine/offline-audio-storage.ts` |
| Snapshot | `front_vibes/src/services/offline-vibe-cache.service.ts` |
| API resource | `back_vibes/app/Http/Resources/VibeSoundResource.php` |
