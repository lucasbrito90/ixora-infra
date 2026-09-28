# ADR-043: Mobile persistence for the KMP rebuild — SQLDelight and DataStore

## Status

**Proposed** (2026-09-28) — governs how the `ixora-app` Kotlin Multiplatform rebuild persists local data on the device: the schedule mirror, the two offline manifests, and non-sensitive user preferences. Token and credential storage are **not** in scope — that concern was closed by [ADR-044](ADR-044-firebase-auth-kmp.md).

PO authorised Phase 3 on 2026-09-27. This ADR is written as part of K18 (Phase 3 backlog definition) and is **pending PO approval**; no implementation should start before approval (that implementation is card K22).

## Date

2026-09-28

---

## 1. Problem

`commonMain` needs a persistence story for three kinds of local state that exist in `front_vibes` today and have no KMP-native equivalent yet:

1. A **read-only mirror of schedules**, kept for offline scheduling decisions.
2. Two **offline manifests** (audio files on disk, and a minimal vibe/sound snapshot) that let playback continue without the API.
3. A handful of **non-sensitive preferences** (theme, push-token bookkeeping, scheduled-notification bookkeeping).

Token and credential storage is explicitly **not** part of this problem: [ADR-044](ADR-044-firebase-auth-kmp.md) already decided that the Firebase SDK holds the session natively and the app stores no token at all, so the historical scope of this ADR (`kmp-migration-plan.md` §13: "Persistência mobile: SQLDelight, DataStore **e armazenamento seguro do token**") is narrower than originally planned.

The question is: what storage mechanism serves each of the three kinds of state above, on both Android and iOS, from `commonMain`?

---

## 2. Context

### 2.1 What `front_vibes` persists locally today (measured in `front_vibes` @ `1cf858e`)

**Schedule mirror** — `src/services/schedule-mirror/schedule-mirror-db.adapter.ts` defines the schema as a SQL string, `SCHEDULES_MIRROR_SCHEMA`:

```sql
CREATE TABLE IF NOT EXISTS mirror_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS schedules_mirror (
  id INTEGER PRIMARY KEY NOT NULL,
  vibe_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  timezone TEXT NOT NULL,
  start_time TEXT NOT NULL,
  recurrence_type TEXT NOT NULL,
  recurrence_config TEXT NULL,
  is_enabled INTEGER NOT NULL,
  next_run_at TEXT NULL,
  last_run_at TEXT NULL,
  created_at TEXT NULL,
  updated_at TEXT NULL,
  synced_at TEXT NOT NULL,
  raw_json TEXT NOT NULL
);
```

`src/services/schedule-mirror/capacitor-schedule-mirror-db.adapter.ts` implements this against `@capacitor-community/sqlite` on Android (native SQLite); the interface `ScheduleMirrorDbAdapter` (same file as the schema) also has an in-memory implementation (`in-memory-schedule-mirror-db.adapter.ts`) used in tests and non-native builds. The sync/decision logic that decides when to read the mirror versus the API lives in `src/services/schedule-mirror.service.ts` (201 lines) and is already classified in the migration plan §2.2 SHARED table as "Espelho SQLite de schedules (lógica) ≈200" — **that logic is out of scope for this ADR**; it is pure logic that migrates to `commonMain` regardless of the storage driver, and its port is card K22, not this decision.

**Offline manifests** — two distinct, both live and both consumer-backed:

- `src/services/audio-engine/offline-audio-storage.ts`: key `ixora_offline_audio_manifest_v1`, persisted via `Preferences.set({ key: MANIFEST_KEY, value: JSON.stringify(manifest) })` (line 73; read at line 63). Its header comment: "Persists vibe sound files under `Directory.Data` for guaranteed offline playback." Consumed by `VibePlayerPage.vue`, `offline-downloads.service.ts`, `native-audio.engine.ts`, `native-qa-diagnostics.ts`, `PlayerDebugPanel.vue`.
- `src/services/offline-vibe-cache.service.ts`: key `offline_vibe_manifest_v1`, same `Preferences.set`/`.get` pattern (lines 62/49). Its own header comment explicitly distinguishes it from the audio manifest: *"This is separate from `ixora_offline_audio_manifest_v1` (audio bytes on disk)."* Consumed by `VibePlayerPage.vue`, `SettingsPage.vue`, `offline-downloads.service.ts`, `native-qa-diagnostics.ts`.

Both manifests are today JSON blobs inside Capacitor `Preferences` — a flat key-value store, not a database. The migration plan §6.3 already has an explicit instruction for this: *"Áudio offline: arquivos em disco, com manifesto em SQLDelight em vez de preferências."* This ADR treats both manifests (audio bytes and the vibe/sound snapshot) as instances of that same instruction, since they are the same kind of structured, growing local record that a flat preference key is a poor fit for at scale (a single JSON blob rewritten on every change).

**Non-sensitive preferences** — three found, all single scalar or small-list values in Capacitor `Preferences`, none of them the Firebase ID token:

- `src/composables/useThemeMode.ts`: key `ixora_theme_mode_v1`, one string (`system`/`light`/`dark`) — line 71 (get), line 87 (set).
- `src/services/push-token.service.ts`: keys `PUSH_TOKEN_ID_PREFS_KEY` and `PUSH_TOKEN_PREVIEW_PREFS_KEY` (lines 154–170). Per the file's own doc comment (line 11): *"token_preview are persisted in Capacitor Preferences."* This is a device-registration bookkeeping pair (a numeric row id and a masked preview string) for FCM push tokens — a different, non-sensitive concern from the Firebase **ID token** that ADR-044 closed.
- `src/services/schedule-notification.service.ts`: key `PREFS_SCHEDULED_IDS_KEY` (lines 58/67) — a JSON array of native local-notification ids, kept so they can be cancelled/rescheduled.

### 2.2 Token storage is already closed

[ADR-044](ADR-044-firebase-auth-kmp.md) §2.3 and its Decision 6 already establish that the new app **stores no token**: the native Firebase SDK holds the session, and `AuthTokenProvider` is called on demand. `kmp-migration-plan.md` §13's ADR-043 row was already edited by K13 to record "escopo reduzido: armazenamento seguro do token de autenticação fechado pela ADR-044." This ADR does not reopen that; it only registers what remains.

### 2.3 A stale cross-reference found in the plan (reported, not fixed here)

`kmp-migration-plan.md` §6.3 says: *"Áudio offline: arquivos em disco, com manifesto em SQLDelight em vez de preferências. Ver §15, questão 6."* Today, §15 question 6 reads *"Dados existentes no aparelho migram? — Fechada por D3"* — a different topic (no local-data migration, i.e. no carryover from the old app), not offline audio storage. The numbering in §15 was evidently re-ordered after this cross-reference was written (D1–D9 close several questions and the surviving open ones were renumbered), leaving a dangling pointer. This ADR does not correct §6.3's cross-reference — that is a small, unrelated documentation fix outside this card's scope — but flags it here so the PO can decide whether to fix it separately.

---

## 3. Alternatives considered

### For the schedule mirror and the offline manifests

| Option | KMP maturity | Pros | Cons |
| --- | --- | --- | --- |
| **SQLDelight** (chosen) | High | SQL verified at compile time; stable Android and Native drivers; typed query results; the current use is modest (a read-only mirror plus two manifests), so hand-written SQL is not a burden | iOS driver maturity matters more here than annotation convenience — this is exactly the trade the migration plan §6.3 already made for the schedule mirror |
| Room KMP | Growing | Familiar to Android developers; automatic migrations | KSP on native targets still has friction; newer to KMP than SQLDelight |
| Keep flat key-value (status quo, Preferences-equivalent / DataStore) | — | Nothing to build | This is precisely what the plan's §6.3 instruction rejects for the audio manifest, and by the same reasoning for the vibe-cache manifest: a single growing JSON blob rewritten on every change, no query capability, no partial update |

**Recommendation (already made by the plan, formalised here): SQLDelight**, for all three: `schedules_mirror`/`mirror_meta`, the offline audio manifest, and the offline vibe/sound manifest.

### For non-sensitive preferences

| Option | Pros | Cons |
| --- | --- | --- |
| **`androidx.datastore`** (chosen) | Multiplatform; coroutines/Flow native; already the plan's §6.3 recommendation ("coroutines/Flow nativos") | None identified for this small, scalar use case |
| SQLDelight for preferences too | One less dependency | Overkill for 3–4 scalar/small-list keys; loses the Flow-native ergonomics DataStore gives for reactive settings (e.g. theme) |

**Recommendation: `androidx.datastore`**, matching the plan.

---

## 4. Decision

### Decision 1 — SQLDelight owns the schedule mirror

`commonMain` gets a SQLDelight schema mirroring `mirror_meta` and `schedules_mirror` exactly as measured in §2.1 above (table names, column names and nullability may be adapted to SQLDelight/Kotlin naming conventions in the implementation card, K22 — but no column is dropped or renamed without saying so there). A read repository sits on top, returning `Result<T, DomainError>` (ADR-041 Decision 5). The pure sync/decision logic in `schedule-mirror.service.ts` is ported separately (K22), independent of this storage decision.

### Decision 2 — SQLDelight owns both offline manifests

The offline audio manifest (`ixora_offline_audio_manifest_v1`) and the offline vibe/sound cache manifest (`offline_vibe_manifest_v1`) each get their own SQLDelight table(s) in `commonMain`, replacing the single-blob-in-Preferences pattern, per the plan §6.3 instruction. They remain two distinct schemas — the source files themselves treat them as separate concerns, and this ADR does not merge them. Exact column shapes are decided in the implementation card (K22), by reading each TypeScript manifest's fields, not invented here.

### Decision 3 — DataStore owns non-sensitive preferences

`androidx.datastore` (Preferences DataStore, multiplatform) holds: the theme choice (Sistema/Claro/Escuro — this closes the open dependency that card `UI-11` records: *"Onde guardar a preferência depende da ADR-043"*), the push-token bookkeeping pair (id + masked preview — never the raw device token or the Firebase ID token), and the scheduled local-notification id list. Any other non-sensitive preference discovered later that fits this shape (small scalar or short list, not sensitive, not a growing structured record) also belongs here by the same reasoning, without needing a new ADR (ADR-038 Decision 6: classifying something new without reopening the ADR).

### Decision 4 — Token and credentials remain out of scope

Confirmed as already decided: no token, no credential, no PII goes into SQLDelight or DataStore. [ADR-044](ADR-044-firebase-auth-kmp.md) is the binding decision on that; this ADR does not touch it.

### Decision 5 — Drivers, one per platform, via the standard SQLDelight Gradle setup

Android: `AndroidSqliteDriver` (Gradle artifact `app.cash.sqldelight:android-driver`). Native (iOS): `NativeSqliteDriver` (Gradle artifact `app.cash.sqldelight:native-driver`). Confirmed against the official SQLDelight documentation (`https://sqldelight.github.io/sqldelight/2.1.0/multiplatform_sqlite/`) at the time of writing; the implementation card (K22) pins the exact version against what is compatible with the Kotlin 2.3.20 / AGP 8.13.0 toolchain already in use, the same way K14 pinned Ktor.

### Decision 6 — No infrastructure ahead of a consumer

This ADR only creates SQLDelight and DataStore because a concrete, measured consumer already exists for each (the schedule mirror and the two manifests exist today; the theme choice and the two preference pairs exist today). Nothing here is built in anticipation of a future need (ADR-038 Decision 4: no anticipatory infrastructure) — unlike the token-storage abstraction ADR-044 explicitly deferred.

---

## 5. Consequences

**Positive**

- The audio and vibe-cache manifests stop being single-blob JSON rewrites in a flat key-value store, gaining typed, queryable, partially-updatable storage — directly what the plan asked for.
- One persistence technology (SQLDelight) covers all three structured-data needs (schedule mirror, two manifests), instead of three bespoke formats.
- DataStore's Flow-native API fits the theme preference's reactive consumption pattern (the UI observes the current mode) better than a plain key-value get/set.
- No new abstraction was built for token storage, because none is needed (ADR-044).

**Negative, accepted**

- Two distinct manifest schemas (audio, vibe cache) means two SQLDelight `.sq` files/table sets to maintain, not one — accepted because the source data is genuinely two separate concerns (confirmed by the TypeScript files' own comments) and merging them would be a bigger, unrequested change.
- SQLDelight requires hand-written SQL and manual migrations (no annotation-based schema generation like Room) — accepted per the plan's own trade-off in §6.3, given the modest current scope.

**Risks**

- **Schema drift risk during port (K22).** The three SQLDelight schemas must be read from the real TypeScript definitions cited in §2.1, not re-derived from memory or convention — the same discipline the K19/K22 cards already require.
- **DataStore key naming.** Reusing the same logical keys (theme, push-token id/preview, scheduled-notification ids) across a DataStore `Preferences` instance requires distinct `Preferences.Key` instances; a naming collision would silently overwrite unrelated state. K22 must test this explicitly.

---

## 6. Relationship to other ADRs

- **[ADR-044](ADR-044-firebase-auth-kmp.md)** — closes token/credential storage; this ADR explicitly excludes that concern and only registers the resulting scope reduction (already noted in the plan's §13 ADR-043 row).
- **[ADR-041](ADR-041-state-swift-interop.md)** — the repositories built on top of SQLDelight and DataStore in K22 return `Result<T, DomainError>` (Decision 5) like every other repository in `commonMain`.
- **[ADR-038](ADR-038-kmp-shared-layer.md)** — Decision 4 ("no anticipatory infrastructure," the same reading ADR-044 already used) backs Decision 6 above; Decision 5 (the `CommonMainBoundaryTest` scanner) continues to apply to any new `commonMain` code this ADR's implementation adds.
- **[ADR-042](ADR-042-migration-repository.md)** — consistent with the migration strategy; does not alter it.

---

## 7. Sources

Code inspected 2026-09-28 in `front_vibes` @ `1cf858e` (confirmed: `git -C front_vibes rev-parse --short HEAD`):

- `src/services/schedule-mirror/schedule-mirror-db.adapter.ts` — `SCHEDULES_MIRROR_SCHEMA` (full `CREATE TABLE` for `mirror_meta` and `schedules_mirror`), interface `ScheduleMirrorDbAdapter`.
- `src/services/schedule-mirror/capacitor-schedule-mirror-db.adapter.ts` — native Android implementation via `@capacitor-community/sqlite`.
- `src/services/schedule-mirror/in-memory-schedule-mirror-db.adapter.ts` — non-native/test implementation.
- `src/services/schedule-mirror.service.ts` (201 lines) — sync/decision logic, out of scope for this ADR (card K22).
- `src/services/audio-engine/offline-audio-storage.ts` — `MANIFEST_KEY = 'ixora_offline_audio_manifest_v1'` (line 20); `Preferences.get`/`.set` (lines 63/73); header comment on scope.
- `src/services/offline-vibe-cache.service.ts` — `MANIFEST_KEY = 'offline_vibe_manifest_v1'` (line 14); `Preferences.get`/`.set` (lines 49/62); header comment distinguishing it from the audio manifest.
- `src/composables/useThemeMode.ts` — `STORAGE_KEY = 'ixora_theme_mode_v1'` (line 10); `Preferences.get`/`.set` (lines 71/87).
- `src/services/push-token.service.ts` — `PUSH_TOKEN_ID_PREFS_KEY`, `PUSH_TOKEN_PREVIEW_PREFS_KEY` (lines 154–170); doc comment on token-preview persistence (line 11).
- `src/services/schedule-notification.service.ts` — `PREFS_SCHEDULED_IDS_KEY` (lines 58/67).
- Consumer confirmation via `grep -rl` for each manifest service: `VibePlayerPage.vue`, `SettingsPage.vue`, `offline-downloads.service.ts`, `native-qa-diagnostics.ts`, `native-audio.engine.ts`, `PlayerDebugPanel.vue`.

External documentation: SQLDelight multiplatform SQLite drivers, `https://sqldelight.github.io/sqldelight/2.1.0/multiplatform_sqlite/` — `AndroidSqliteDriver` (`app.cash.sqldelight:android-driver`), `NativeSqliteDriver` (`app.cash.sqldelight:native-driver`).

Internal: [`kmp-migration-plan.md`](../architecture/mobile/kmp-migration-plan.md) §6.3 (persistence recommendation), §13 (ADR-043 row), §16.7 (secure storage requirement, closed by ADR-044), §16.8 (user preferences); card `UI-11` (Settings, depends on this ADR for where the theme choice is stored); card K22 (implementation).
