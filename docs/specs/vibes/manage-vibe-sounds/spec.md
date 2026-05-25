# Manage Vibe Sounds — attach and configure catalog layers (mobile)

**Status:** Active feature specification (source of truth)  
**Version:** 1.0 (matches current `back_vibes` + `front_vibes` implementation)  
**Feature ID:** `vibes/manage-vibe-sounds`  
**Supersedes:** [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) (placeholder — use this spec for product and implementation alignment)

---

## Goal

Enable an **authenticated vibe owner** to **manage sound layers** on an existing personal vibe: browse the **catalog**, **attach** and **detach** existing sounds via **`vibe_sounds`**, **configure** per-layer playback settings (volume, mode, timing), and feed **`buildVibeExecutionPlan`** for mobile playback — **without** creating catalog sounds or uploading audio to Spaces.

**Success criteria:**

- **`vibe_sounds`** links an **existing vibe** to **existing catalog `sounds`** only.
- **Create Sound** does **not** create pivot rows — attach is a separate step ([`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md)).
- Nested routes **`GET/POST/PATCH/DELETE /api/vibes/{vibe}/sounds`** are the **only** layer mutation API (no new endpoints).
- **`VibePolicy::update`** gates attach/detach/configure; **`view`** gates list.
- **`play_mode`** drives **`loop`** server-side; **interval** mode requires **`repeat_interval_seconds`**.
- Playback uses catalog **`file_url`** (HTTPS CDN); fade pivot fields are **ignored at runtime**.
- **Offline snapshots** include **`vibeSounds[]`** only after successful **Download for offline** ([`../offline-download/spec.md`](../offline-download/spec.md)).

---

## Scope

### In scope

- **List layers:** `GET /api/vibes/{vibe}/sounds`
- **Attach layer:** `POST /api/vibes/{vibe}/sounds` with `sound_id` + pivot fields
- **Update layer:** `PATCH /api/vibes/{vibe}/sounds/{sound}`
- **Detach layer:** `DELETE /api/vibes/{vibe}/sounds/{sound}`
- **Mobile UX:** **`VibeSoundsPage`** (`/vibes/:id/sounds`) — catalog browse, selection, bulk save (attach/remove), **`VibeSoundEditModal`** per-layer config
- **Catalog read:** `GET /api/sounds` for library (read-only in this flow)
- **Execution plan:** **`buildVibeExecutionPlan(vibeSounds)`** on player and sounds page
- **Pivot fields:** volume, sort_order, play_mode, loop (derived), repeat_interval_seconds, start_offset_seconds, play_duration_seconds, fade_in_seconds, fade_out_seconds

### Out of scope

- **Creating catalog sounds** — admin **Create Sound** only
- **Uploading audio** to Spaces from mobile — **not implemented**
- **Creating or updating vibes** metadata/visuals — [`../create-vibe/spec.md`](../create-vibe/spec.md), [`../update-vibe/spec.md`](../update-vibe/spec.md)
- **Preset vibe layers** (`preset_vibe_sounds`, admin sync API)
- **Admin UI** for user vibe layers (mobile-first today)
- **Audio transcoding / processing**
- **Runtime fade playback** — fields may be stored; engine does not apply fades
- **Collaborative / shared layer editing**
- **New nested endpoints** beyond current four verbs

---

## Actors

| Actor | Role |
| --- | --- |
| **End user (vibe owner)** | Selects catalog sounds, saves attach/detach, edits layer settings. |
| **Mobile app (`front_vibes`)** | Calls nested vibe-sound APIs + catalog list; builds execution plan. |
| **Laravel API (`back_vibes`)** | Enforces policies; validates requests; mutates **`vibe_sounds`** pivot only. |
| **Catalog (`sounds`)** | Reusable audio assets with **`file_url`** — referenced by **`sound_id`**, never created here. |
| **`vibes`** | User-owned composition — layers require **`update`** permission on parent vibe. |

---

## User Journey

1. User opens **Manage sounds** on a vibe → `/vibes/:id/sounds` (**`VibeSoundsPage`**).
2. App loads in parallel:
   - **`GET /api/sounds`** — catalog library
   - **`GET /api/vibes/{id}/sounds`** — current layers
3. User toggles catalog cards to add/remove sounds from **selection** (local state).
4. User taps **Save Sounds** → parallel **`POST`** (attach new) and **`DELETE`** (detach removed) → **`fetchVibeSounds`** → **`router.back()`**.
5. For an **already attached** sound, user opens **edit** (layer settings) → **`VibeSoundEditModal`** → **`PATCH /api/vibes/{id}/sounds/{soundId}`** with volume, play_mode, timing.
6. User plays vibe on **`VibePlayerPage`** → loads layers → **`buildVibeExecutionPlan`** → native playback via catalog **`file_url`**.

**Default attach on bulk save (mobile):** `volume: 80`, `loop: true`, `sort_order: 0` — server sets **`play_mode`** default **`loop`** and derives **`loop`** from mode.

---

## Related Domain Model

```
┌─────────────┐         vibe_sounds          ┌─────────────┐
│   sounds    │◄──── (pivot configuration) ──►│    vibes    │
│  (catalog)  │      UNIQUE(vibe_id,sound_id) │ (user-owned)│
└─────────────┘                               └─────────────┘
       │                                              │
       │ file_url (CDN HTTPS)                         │ owner user_id
       │ thumbnail_url (preview UI)                   │
       └──────────────────┬───────────────────────────┘
                          ▼
                 buildVibeExecutionPlan
                 → VibePlayerPage / native audio
```

| Entity | Owns | Does not own |
| --- | --- | --- |
| **`sounds`** | Catalog metadata, **`file_url`**, **`thumbnail_url`** | Per-vibe volume, mode, order |
| **`vibes`** | Composition identity, visuals, **`user_id`** | Layer config (pivot) |
| **`vibe_sounds`** | volume, sort_order, play_mode, loop, timing, fade fields | Audio bytes; catalog row creation |

**Create Sound** inserts **`sounds`** only — **no `vibe_sounds`**. **Manage sounds** inserts/updates/deletes **`vibe_sounds`** only — **no `sounds`**.

Parallel admin model: **`preset_vibe_sounds`** — out of scope ([`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) historical note).

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Only **authenticated Firebase-synced users** may call vibe-sound routes. |
| FR-2 | **`GET …/sounds`** requires **`authorize('view', $vibe)`** (owner). |
| FR-3 | **`POST/PATCH/DELETE …/sounds`** requires **`authorize('update', $vibe)`** (owner). |
| FR-4 | **Attach** references **`sound_id`** that **exists** in **`sounds`** — does not create catalog rows. |
| FR-5 | **One pivot row per (vibe_id, sound_id)** — duplicate attach rejected (DB unique constraint). |
| FR-6 | **Detach** removes pivot row only — catalog **`sounds`** row remains. |
| FR-7 | **`play_mode`** is source of truth: **`loop` \| `once` \| `interval`**. |
| FR-8 | Server **derives `loop = (play_mode === 'loop')`** — not trusted from client alone on attach/update when mode is present. |
| FR-9 | When **`play_mode === 'interval'`**, **`repeat_interval_seconds`** is required (min 1) on attach/update. |
| FR-10 | When mode is not **interval**, server clears **`repeat_interval_seconds`** on attach; update strips orphan interval if mode omitted. |
| FR-11 | **Default attach:** volume **80**, **`play_mode` `loop`**, **`sort_order` 0** when omitted (controller defaults). |
| FR-12 | **`VibeSoundResource`** merges **sound** fields + **pivot** fields; **`file_url`** from catalog for playback. |
| FR-13 | Mobile **`buildVibeExecutionPlan`** sorts by **`sort_order`**, maps timing/mode; **`fileUrl`** = **`vs.file_url`**. |
| FR-14 | **`fade_in_seconds` / `fade_out_seconds`** may be stored and appear in plan — **not applied at runtime** ([`audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md)). |
| FR-15 | Mobile edit modal does **not** expose fade controls today — API still accepts fade fields if sent. |
| FR-16 | **No Spaces upload** in manage-sounds flow — playback URLs are catalog HTTPS strings only. |
| FR-17 | **Offline `vibeSounds[]`** in **`offline_vibe_manifest_v1`** written only on successful **Download for offline**, not on layer save. |

---

## Validation Rules

### Attach (`AttachVibeSoundRequest`)

| Field | Rules |
| --- | --- |
| `sound_id` | Required, integer, **`exists:sounds,id`** |
| `volume` | Optional, integer 0–100 |
| `sort_order` | Optional, integer ≥ 0 |
| `play_mode` | Optional, **`loop` \| `once` \| `interval`** |
| `repeat_interval_seconds` | Nullable integer ≥ 1; **`required_if:play_mode,interval`** |
| `start_offset_seconds` | Nullable integer ≥ 0 |
| `play_duration_seconds` | Nullable integer ≥ 1 |
| `fade_in_seconds`, `fade_out_seconds` | Nullable integer ≥ 0 |

### Update (`UpdateVibeSoundRequest`)

| Field | Rules |
| --- | --- |
| `volume`, `sort_order` | Optional (`sometimes`), same bounds as attach |
| `play_mode` | Optional; **`in:loop,once,interval`** |
| `repeat_interval_seconds` | **`required_if:play_mode,interval`** when mode sent |
| Timing / fade fields | Same as attach |

### Server invariants (`VibeSoundController`)

| Rule | Behaviour |
| --- | --- |
| `loop` derivation | Set from **`play_mode`** on attach; re-derived on update when **`play_mode`** present |
| Interval cleanup | Non-interval modes → **`repeat_interval_seconds`** null on attach |
| Orphan interval | If update sends **`repeat_interval_seconds`** without **`play_mode`** → field **unset** |

### Mobile bulk attach defaults (`VibeSoundsPage`)

| Field | Value on new attach |
| --- | --- |
| `volume` | 80 |
| `loop` | true (client hint; server uses default **`play_mode` `loop`**) |
| `sort_order` | 0 |

### Mobile layer edit (`VibeSoundEditModal`)

| Field | UI behaviour |
| --- | --- |
| `volume` | 0–100 slider |
| `play_mode` | loop / once / interval |
| `repeat_interval_seconds` | Shown only for interval |
| `start_offset_seconds`, `play_duration_seconds` | Minutes in UI → seconds in API |
| Fades | Not exposed in UI |

---

## API Contract

All routes under **`firebase.auth`**. `{sound}` route parameter is catalog **`sounds.id`**.

### List layers

```
GET /api/vibes/{vibe}/sounds
```

**Policy:** **`view`** (owner)

**Success: 200 OK** — array of **`VibeSoundResource`**:

| Field | Source |
| --- | --- |
| `id`, `name`, `file_url`, `thumbnail_url`, `category`, `duration` | **Sound** catalog |
| `volume`, `loop`, `sort_order`, `play_mode`, timing, fades | **Pivot** |

### Attach layer

```
POST /api/vibes/{vibe}/sounds
```

**Policy:** **`update`** (owner)

**Body (JSON):**

```json
{
  "sound_id": 5,
  "volume": 80,
  "sort_order": 0,
  "play_mode": "loop"
}
```

**Success:** **201** + **`VibeSoundResource`** (single layer)

### Update layer

```
PATCH /api/vibes/{vibe}/sounds/{sound}
```

**Policy:** **`update`** (owner)

**Body (JSON):** partial pivot fields (see Validation Rules)

**Success:** **200** + **`VibeSoundResource`**

### Detach layer

```
DELETE /api/vibes/{vibe}/sounds/{sound}
```

**Policy:** **`update`** (owner)

**Success:** **200** `{ "message": "Sound removed from vibe." }`

### Catalog read (manage UI)

```
GET /api/sounds
```

**Auth:** `firebase.auth` — list active catalog for picker (not nested under vibe).

### Error responses (common)

| HTTP | Condition |
| --- | --- |
| **401** | Missing/invalid Firebase token |
| **403** | Not vibe owner |
| **404** | Vibe or sound not found |
| **422** | Validation (invalid `sound_id`, interval without seconds, etc.) |
| **409/500** | Duplicate attach (`uq_vibe_sounds_vibe_sound`) — treat as client error to avoid double attach |

**No additional endpoints** (bulk sync, reorder-only, embed in vibe PATCH) in current architecture.

---

## Mobile UX Rules

| Surface | Rules |
| --- | --- |
| **`VibeSoundsPage`** | Route **`/vibes/:id/sounds`**; hero + catalog grid + selected chips |
| Selection | Toggle adds/removes **local** `selectedIds` before save |
| **Save Sounds** | Parallel attach/remove via **`vibeSoundService`** (not composable — avoids loading race) |
| After save | Re-fetch layers, sync selection, toast, **`router.back()`** |
| **Edit layer** | Sheet modal **`VibeSoundEditModal`** for attached sounds only |
| Catalog filters | Search, category chips, mood tags — presentation only |
| Preview thumbs | Catalog **`thumbnail_url`** — not layer playback |
| Execution plan | **`watch(vibeSounds)` → `buildPlan`** on page for local preview semantics |
| Auth | Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |

---

## Playback Behaviour

| Topic | Behaviour |
| --- | --- |
| Plan builder | **`buildVibeExecutionPlan(vibeSounds)`** in **`player-engine.service.ts`** |
| Ordering | Sort ascending **`sort_order`** |
| Audio URL | **`layer.fileUrl`** = catalog **`file_url`** (HTTPS CDN) |
| Playable check | **`isExecutionLayerPlayable`**: valid URL; interval requires **`repeatIntervalSeconds ≥ 1`** |
| Modes | **`loop`**, **`once`**, **`interval`** — native engine in **`audio-player.service.ts`** |
| Fades | In plan as **`fadeInSeconds` / `fadeOutSeconds`** default 0 — **not applied at runtime** |
| Offline resolve | **`resolvePlaybackAssetUrl`**: **`file://`** when audio manifest **`remoteUrl === layer.fileUrl`** ([`../offline-download/spec.md`](../offline-download/spec.md)) |
| Streaming cache | ExoPlayer SimpleCache during HTTPS play — **best-effort**, not manage-sounds scope |

Manage sounds **configures** layers; **VibePlayerPage** **plays** them from the same API shape.

---

## Offline Behaviour

| Topic | Behaviour |
| --- | --- |
| Layer save | **Does not** update **`offline_vibe_manifest_v1`** or **`ixora_offline_audio_manifest_v1`** |
| Snapshot | **`offline_vibe_manifest_v1`** stores **`vibeSounds[]`** copy **only after** successful **Download for offline** (`failed === 0`) |
| Stale offline | User changes layers online → offline snapshot **stale** until re-download |
| Player offline | Hydrates from snapshot when API fails; plan from snapshot sounds |
| URL match | Offline audio files keyed by exact **`layer.fileUrl`** at download time |

Changing layers after download does not auto-refresh offline bytes or snapshot.

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Non-owner list/attach/update/delete | **403** |
| Invalid `sound_id` | **422** |
| Duplicate attach same sound | DB unique violation — avoid in UI (already attached) |
| Interval mode without interval seconds | **422** |
| Empty catalog | Empty state on **`VibeSoundsPage`** |
| Partial parallel save failure | Toast error; user may retry; re-fetch recommended |
| Catalog sound inactive | May still attach if row exists — product may filter client-side |
| Missing `file_url` on sound | Layer non-playable in execution plan |
| Delete catalog sound in use | Admin delete blocked elsewhere (**409**) — pivot still references until detached |
| Offline manage sounds | Requires network for API mutations |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Identity | Firebase Bearer on all requests |
| Ownership | **`VibePolicy`** — only owner mutates layers |
| Catalog create | No **`POST /api/sounds`** from manage flow |
| Trust boundary | **`sound_id`** must exist in catalog — no arbitrary URL fields on pivot |
| Playback URLs | From **`sounds.file_url`** only — opaque HTTPS |
| Secrets | No **`DO_SPACES_*`** on mobile |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| Reorder UI | **`sort_order`** editable — currently read-only badge in edit modal |
| Fade UI | Hidden until native engine supports runtime fades |
| Bulk PATCH / sync endpoint | Not today — parallel POST/DELETE on save |
| Admin layer editor | ixora-admin — separate spec |
| Auto-refresh offline on layer change | Not implemented |
| Max layers per vibe | No server cap documented yet |

**Explicitly excluded:** new nested routes, catalog create in manage flow, Spaces upload, transcoding, collaborative editing.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/manage-vibe-sounds/spec.md` |
| Placeholder (superseded) | [`../vibe-sounds/spec.md`](../vibe-sounds/spec.md) |
| Create Sound | [`../../sounds/create-sound/spec.md`](../../sounds/create-sound/spec.md) |
| Create / update vibe | [`../create-vibe/spec.md`](../create-vibe/spec.md), [`../update-vibe/spec.md`](../update-vibe/spec.md) |
| Offline download | [`../offline-download/spec.md`](../offline-download/spec.md) |
| Fade limitations | [`docs/architecture/audio/audio-engine-fade-limitations.md`](../../../architecture/audio/audio-engine-fade-limitations.md) |
| Audio cache | [`docs/architecture/audio/audio-cache.md`](../../../architecture/audio/audio-cache.md) |
| Storage / CDN | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| **back_vibes** | `VibeSoundController.php`, `AttachVibeSoundRequest.php`, `UpdateVibeSoundRequest.php`, `VibeSoundResource.php`, `VibeSound.php` |
| **front_vibes** | `VibeSoundsPage.vue`, `VibeSoundEditModal.vue`, `vibe-sound.service.ts`, `player-engine.service.ts` |

When behaviour changes, update **this file first**, then align API, mobile UI, and cross-linked specs.
