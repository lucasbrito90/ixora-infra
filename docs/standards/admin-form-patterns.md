# Admin form patterns — ixora-admin catalog forms

**Status:** Active engineering standard (source of truth)  
**Scope:** Form composition, submission, upload, error handling, and API integration patterns for **`ixora-admin`** catalog CRUD  
**Applies to:** `ixora-admin` components, composables, services — primary reference implementations: **`SoundForm`**, **`CoverBundleForm`**

---

## Purpose

Define the **mandatory admin form architecture** for Ixora catalog maintenance: how Nuxt pages compose form components, how **multipart create** and **edit/update** flows differ, how uploads reach Laravel (never Spaces directly), how Laravel **422** errors become user-facing messages, and how loading states prevent duplicate submits.

**Admin uploads go through Laravel only.** The browser holds **Firebase ID tokens** and **`NUXT_PUBLIC_API_BASE_URL`** — **no `DO_SPACES_*` credentials**. CDN URLs appear in the UI **only after** Laravel persists them and returns **`SoundResource`** / **`CoverBundleResource`** JSON (or generic upload **`data.url`**).

This document is the **source of truth** for humans and AI-assisted admin work. Feature specs reference concrete flows but do not replace this standard.

---

## Scope

### In scope

- Form component patterns (`SoundForm.vue`, `CoverBundleForm.vue`)
- Page wrappers (`pages/sounds/*`, `pages/covers/*`) — **create vs edit** separation
- Composables: **`useSounds`**, **`useCoverBundles`**, **`useUpload`**, **`useFirebaseAuth`**, **`useLaravelAccessRedirect`**
- Services: **`sound.service.ts`**, **`cover-bundle.service.ts`**, **`upload.service.ts`**, **`laravel-api-error.ts`**
- **Single-submit multipart create** (sound + cover bundle)
- **Edit-mode incremental upload** via **`POST /api/admin/uploads`** (XHR)
- **Friendly API message** normalization (`friendlySoundApiMessage`, `friendlyCoverBundleApiMessage`, `friendlyLaravelUploadHttpError`)
- Laravel **`{ data }`** envelope parsing
- Auth middleware + **403 admin not approved** redirect
- Client UX hints from **`shared/upload-limits.ts`** (non-authoritative)

### Out of scope

- **Direct browser-to-Spaces** uploads, presigned URLs, chunk/resumable upload UI
- **Mobile (`front_vibes`)** forms — no admin upload client on mobile
- **Realtime collaborative admin**, websocket progress sync, autosave drafts
- **AI media generation**, image processing pipelines, virus scanning
- **Optimistic fake success** or local-only persistence without API confirmation
- **Client-generated CDN URLs** — URLs always from API response or loaded entity

### Applies to

| Layer | Location |
| --- | --- |
| Form components | `ixora-admin/components/SoundForm.vue`, `CoverBundleForm.vue` |
| Pages | `pages/sounds/create.vue`, `[id]/edit.vue`, `pages/covers/create.vue`, `[id]/edit.vue` |
| Domain composables | `composables/useSounds.ts`, `useCoverBundles.ts`, `useUpload.ts` |
| HTTP services | `services/api/sound.service.ts`, `cover-bundle.service.ts`, `upload.service.ts` |
| Error helpers | `services/api/laravel-api-error.ts` |
| Upload hints | `shared/upload-limits.ts` |
| Auth | `composables/useFirebaseAuth.ts`, `middleware/auth.ts`, `services/api/auth.service.ts` |

---

## Form Architecture

### Layer separation

```
Page (create.vue / [id]/edit.vue)
  │  definePageMeta({ layout: 'admin', middleware: ['auth'] })
  │  edit page: load entity → pass :initial
  ▼
Form component (SoundForm / CoverBundleForm)
  │  props: mode: 'create' | 'edit', initial?: Entity
  │  reactive form state, file pickers, submit handler
  ▼
Composable (useSounds / useCoverBundles / useUpload)
  │  optional list state; delegates to service
  ▼
Service (sound.service / cover-bundle.service / upload.service)
  │  $fetch or XHR → Laravel API
  │  unwrap { data }, normalize to TypeScript types
  ▼
Laravel API → JsonResources / upload JSON
```

| Layer | Responsibility |
| --- | --- |
| **Page** | Routing, auth middleware, **edit preload** (`getOne` / `fetch`), load error banner |
| **Form component** | UX sections, validation gates, **`canSubmit`**, **`submit()`**, file pick handlers |
| **Composable** | Reusable list CRUD; **`useUpload`** for edit-mode asset replace |
| **Service** | HTTP contract, **`FormData`** assembly, response normalization |
| **Error module** | **`parseLaravelFetchError`**, friendly message mappers |

### Form composition patterns

| Pattern | Detail |
| --- | --- |
| **Sectioned cards** | “Basic info” + “Media” / “Visual assets” blocks in Tailwind card layout |
| **`mode` prop** | **`'create' \| 'edit'`** drives copy, required files, upload strategy |
| **`initial` prop** | Edit mode hydrates form via **`watch(..., { immediate: true })`** |
| **Tags as CSV** | `tagsRaw` string → **`parseTags()`** → `string[]` for API |
| **Blob previews (create)** | `URL.createObjectURL(file)` for local preview; **`revokeObjectURL`** on unmount |
| **CDN previews (edit)** | `<img>` / `<audio>` use persisted **`file_url`** / **`thumbnail_url`** or post-upload URL |
| **Read-only CDN block (sound edit)** | Displays API-written URLs — not editable paths |

### Create vs edit mode (architectural split)

| Aspect | **Create** | **Edit** |
| --- | --- | --- |
| **Files** | Held in **`pending*File`** refs until submit | Replaced via **`useUpload`** → **`POST /api/admin/uploads`** on pick (sound + cover) |
| **Submit API** | **Single multipart POST** with all files | **PATCH JSON** metadata (+ URLs updated by prior uploads or paste) |
| **CDN URLs before save** | **None** — only blob previews | From **`initial`** or upload response **`data.url`** |
| **Cover URLs on edit** | N/A | Optional **paste HTTPS** in URL inputs **or** upload |
| **Navigation on success** | Sound → **`/sounds/{id}/edit`**; Cover → **`/covers`** | Both → list or stay flow per form |

**Rule:** Create flows **do not** pre-upload via `/api/admin/uploads` — one **`FormData`** POST per [`upload-validation.md`](upload-validation.md).

---

## Submission Rules

### Pre-submit

1. **`saving.value = true`**, clear **`saveError`**
2. **`getToken(true)`** — Firebase ID token with refresh
3. If no token → **`saveError = 'Not authenticated'`**, abort
4. Client-side gates (**`canSubmit`**, explicit checks in **`submit()`**) — UX only; Laravel remains authoritative

### Post-success (no optimistic UI)

| Form | On success |
| --- | --- |
| **Sound create** | **`navigateTo(`/sounds/${created.id}/edit`)`** — entity must exist server-side |
| **Sound edit** | **`navigateTo('/sounds')`** after **`patchSound`** |
| **Cover create** | **`navigateTo('/covers')`** after **`createWithFiles`** |
| **Cover edit** | **`navigateTo('/covers')`** after **`update`** |

**No local-only persistence.** Navigation happens **only after** resolved API promise.

### Submit button disabling

```typescript
// SoundForm — create requires pending files; edit requires metadata
const canSubmit = computed(() => {
  const busy = saving.value || toValue(upload.uploading);
  if (busy) return false;
  // … name, category, duration, tags …
  if (props.mode === 'create') {
    return … && !!pendingAudioFile.value && !!pendingThumbFile.value;
  }
  return …; // edit: metadata only on submit (files uploaded separately)
});

// CoverBundleForm
:disabled="saving || uploadBusy || !canSubmit"
```

| State | Disables submit |
| --- | --- |
| **`saving`** | Primary submit + cover create file pickers |
| **`upload.uploading`** | Sound submit + sound edit file inputs |
| **`uploadBusy`** (cover edit) | Cover submit while XHR upload runs |

---

## Upload Rules

### Architecture (Laravel only)

| Rule | Detail |
| --- | --- |
| **Create** | **`FormData`** on **`POST /api/admin/sounds`** or **`POST /api/cover-bundles`** |
| **Edit replace** | **`uploadAssetViaLaravel`** → **`POST /api/admin/uploads`** (XHR + progress) |
| **Credentials** | **`Authorization: Bearer <token>`** only — no Spaces keys in Nuxt |
| **CDN URL source** | Response **`data.url`** (upload) or normalized resource fields (create **201**) |
| **Limits** | Server **`UploadAssetValidator`** — hints in **`upload-limits.ts`** |

See [`upload-validation.md`](upload-validation.md).

### Sound create — multipart field append

```typescript
// services/api/sound.service.ts — createSoundWithFiles
const fd = new FormData();
fd.append('name', payload.name.trim());
fd.append('category', payload.category.trim());
fd.append('duration_seconds', String(payload.duration_seconds));
fd.append('is_active', payload.is_active ? '1' : '0');
for (const t of payload.tags) {
  fd.append('tags[]', t);
}
fd.append('audio_file', payload.audio_file);
fd.append('thumbnail_file', payload.thumbnail_file);

await $fetch(apiUrl('/api/admin/sounds'), {
  method: 'POST',
  headers: bearerHeaders(token),
  body: fd,
});
```

**SoundForm create flow:** user picks files → **`pendingAudioFile`** / **`pendingThumbFile`** + blob previews → single **`createWithFiles`** on submit.

### Cover bundle create — multipart field append

```typescript
// services/api/cover-bundle.service.ts — createCoverBundleWithFiles
const fd = new FormData();
fd.append('name', payload.name.trim());
if (payload.description?.trim()) fd.append('description', payload.description.trim());
fd.append('category', payload.category.trim());
fd.append('is_active', payload.is_active ? '1' : '0');
for (const t of payload.tags) fd.append('tags[]', t);
fd.append('thumbnail_file', payload.thumbnail_file);
fd.append('artwork_file', payload.artwork_file);
fd.append('player_background_file', payload.player_background_file);

await $fetch(apiUrl('/api/cover-bundles'), { method: 'POST', headers: bearerHeaders(token), body: fd });
```

**CoverBundleForm create flow:** three **`assignCreateSlot`** file refs + blob previews → single **`createWithFiles`** on submit.

### Edit-mode incremental upload (XHR)

```typescript
// services/api/upload.service.ts — uploadAssetViaLaravel
const fd = new FormData();
fd.append('entity_type', params.entityType);   // 'sound' | 'cover'
fd.append('entity_id', String(params.entityId));
fd.append('asset_type', params.assetType);     // 'audio' | 'thumbnail' | 'artwork' | 'player_background'
fd.append('file', params.file);
// POST ${apiBase}/admin/uploads — XMLHttpRequest for upload.onprogress
```

**Sound edit:** **`onAudioPick`** / **`onThumbnailPick`** → **`upload.uploadSoundAudio`** / **`uploadSoundThumbnail`** → assign **`form.file_url`** / **`form.thumbnail_url`** from **`url`**.

**Cover edit:** **`onImagePick`** → **`upload.uploadCoverImage`** → assign matching **`form.*_url`**.

**PATCH on save** persists metadata + current URL strings — uploads already wrote CDN URLs into form state.

### File input UX

| Helper | Usage |
| --- | --- |
| **`AUDIO_ACCEPT_ATTR`** | Sound audio `<input accept>` |
| **`IMAGE_ACCEPT_ATTR`** | Thumbnails / cover images |
| **`AUDIO_UPLOAD_HINT`**, **`IMAGE_UPLOAD_HINT`** | Static copy under Media section |

Server may reject types not in accept list — hints are **not** validation.

---

## Error Handling Rules

### Two error surfaces

| Surface | Variable | Mapper | When |
| --- | --- | --- | --- |
| **Form save/load** | **`saveError`**, **`loadError`**, composable **`error`** | **`friendlySoundApiMessage`**, **`friendlyCoverBundleApiMessage`** | **`$fetch`** failures on create/PATCH/list/get |
| **Edit upload (XHR)** | **`upload.error`** | **`friendlyLaravelUploadHttpError`** | **`uploadAssetViaLaravel`** non-2xx |

### Laravel 422 parsing

```typescript
// services/api/laravel-api-error.ts
export function parseLaravelValidationLines(data: unknown): string[] {
  // Flattens Laravel { errors: { field: ["msg"] } } → ["field: msg", …]
}

export function friendlySoundApiMessage(e: unknown): string {
  const { status, message, validationLines } = parseLaravelFetchError(e);
  if (isAdminAccessNotApprovedError(e)) return ACCESS_REQUEST_REDIRECT_HINT;
  if (status === 401) return 'Your session expired. Please sign in again.';
  if (status === 422) {
    if (validationLines.length) return validationLines.join(' ');
    return message || 'Please check the form and try again.';
  }
  if (status !== undefined && status >= 500) return 'The server is unavailable. Please try again shortly.';
  return message || 'Something went wrong.';
}
```

**`friendlyCoverBundleApiMessage`** and **`friendlyPresetVibeApiMessage`** delegate to **`friendlySoundApiMessage`** — shared Laravel envelope handling.

### Upload error example (413 / 422)

```typescript
export function friendlyLaravelUploadHttpError(status: number, body: unknown): string {
  if (status === 413) return 'File is too large. Audio max 25 MB, images max 5 MB.';
  if (status === 422) {
    const lines = parseLaravelValidationLines(body);
    return lines.length ? lines.join(' ') : 'Invalid file or parameters.';
  }
  // … 401, 403 admin, 5xx, status 0 network …
}
```

Displayed in **`upload.error`** (amber banner on cover form; red under audio on sound form).

### Admin access not approved (403)

| Check | Action |
| --- | --- |
| **`isAdminAccessNotApprovedError(e)`** | **`status === 403`** && message **`Admin access is not approved.`** |
| Form **`submit()`** catch | **`redirectToAccessRequestWithFlash()`** → **`/access-request`** |
| Upload pick catch | Same redirect when error message is **`ACCESS_REQUEST_REDIRECT_HINT`** |

**Client-side:** **`middleware/auth.ts`** routes non-approved users to **`/access-request`** before catalog pages load. **Server-side:** **`admin.approved`** middleware is still authoritative on writes.

### Validation error handling example (form submit)

**Scenario:** Create sound with prohibited `file_url` or oversize audio.

1. Laravel returns **422** `{ message, errors: { audio_file: ["Audio must not exceed 25 MB."] } }`
2. **`$fetch`** throws with **`data`** attached
3. **`friendlySoundApiMessage(e)`** → **`"audio_file: Audio must not exceed 25 MB."`**
4. **`saveError`** red banner — user fixes file and **retries submit** (no auto-retry)

**Cover create missing file:** client **`saveError`** before API — *"Choose thumbnail, artwork, and player background images."*

---

## Loading State Rules

| State | Ref | UI |
| --- | --- | --- |
| **Saving** | **`saving`** | Button label **"Saving…"**; disabled submit |
| **Upload in progress** | **`upload.uploading`**, **`upload.progress`** | Progress bar; disabled file inputs |
| **Slot busy (cover edit)** | **`slotBusy`** | Per-slot progress bar |
| **Page load (edit)** | **`pending`** on page | **"Loading…"** before **`SoundForm`** mounts |
| **List load** | composable **`loading`** | Index page loading copy |

**No websocket / realtime sync** — XHR **`upload.onprogress`** only for edit uploads.

---

## Validation Rules

### Client-side (UX gates — not authoritative)

| Form | Create gates | Edit gates |
| --- | --- | --- |
| **SoundForm** | Name, category, duration ≥ 0, ≥1 tag, **both files** | Name, category, duration |
| **CoverBundleForm** | Name, category, ≥1 tag, **all three image files** | Name; **`looksLikeHttpUrl`** on URL fields if non-empty |

**Server validation** via **`StoreSoundRequest`** / **`StoreCoverBundleRequest`** + **`UploadAssetValidator`** — see [`upload-validation.md`](upload-validation.md) and [`laravel-form-request-patterns.md`](laravel-form-request-patterns.md).

### Field-level rendering

| Pattern | Implementation |
| --- | --- |
| **Banner errors** | **`saveError`**, **`loadError`**, **`upload.error`** — full-width colored paragraphs |
| **Inline field highlight** | CoverBundleForm: **`nameInvalid`**, **`categoryInvalid`**, **`urlFieldInvalid`** → red border classes |
| **SoundForm** | Primarily banner; file requirements enforced via **`canSubmit`** |

**422 field keys** appear in friendly message text (`field: message`) — not separate per-field Laravel error components today.

### Required file handling (create)

| Entity | Required parts |
| --- | --- |
| Sound | **`audio_file`**, **`thumbnail_file`** |
| Cover bundle | **`thumbnail_file`**, **`artwork_file`**, **`player_background_file`** |

Files stay in memory until submit — **not** uploaded incrementally on create.

---

## API Integration Rules

### Auth boundary

```
Firebase sign-in (ixora-admin)
  → POST /api/auth/sync (Bearer Firebase token)
  → LaravelSyncedUser (role, admin_access_status)
  → middleware/auth: isApprovedAdmin → catalog pages
  → All API calls: Authorization: Bearer <Firebase ID token>
  → Catalog writes: Laravel admin.approved middleware
```

Align with [`front-vibes-auth-core.md`](front-vibes-auth-core.md) for shared Firebase → Laravel sync contract; admin adds **`admin_access_status`** gate.

### Response contract — `{ data }` envelope

Per [`api-resource-patterns.md`](api-resource-patterns.md):

```typescript
function unwrapOne(body: unknown): Record<string, unknown> {
  if (body && typeof body === 'object' && 'data' in body) {
    const d = (body as { data: unknown }).data;
    if (d && typeof d === 'object') return d as Record<string, unknown>;
  }
  return {};
}
```

**Normalization** in services maps API aliases to admin types:

| API field | Admin `Sound` type |
| --- | --- |
| **`file_url`** (or legacy **`audio_url`**) | **`file_url`** |
| **`duration`** / **`duration_seconds`** | **`duration_seconds`** |

Cover bundle: **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`** as strings on **`CoverBundle`**.

### CDN URL rendering after persistence

| Moment | URL source |
| --- | --- |
| **After create 201** | Normalized resource from response — navigate before user needs URLs on create page |
| **Edit load** | **`initial`** from **`GET`** — **`form.file_url`**, etc. |
| **After edit upload** | **`uploadAssetViaLaravel`** → **`form.*_url = url`** — immediate preview |
| **Sound edit read-only block** | Displays persisted CDN strings for debugging/verification |

**Never** construct CDN URLs in the client from bucket keys — only use API-returned **`url`** / resource fields.

### PATCH body shaping

Services use dedicated helpers (**`toLaravelSoundPatchBody`**, **`toPatchBody`**) — trim strings, null empty URLs, omit undefined keys pattern via explicit field checks.

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| **No Spaces credentials in admin** | Only **`NUXT_PUBLIC_API_BASE_URL`** + Firebase client config |
| **Bearer on every API call** | **`getToken(true)`** before writes |
| **Admin approval** | Client middleware + server **`admin.approved`** |
| **CORS** | Admin origin in API **`CORS_ALLOWED_ORIGINS`** for multipart POST |
| **No URL bypass on create** | Multipart create — Laravel **`prohibited`** URL fields |
| **No optimistic trust** | Do not show success until API resolves |
| **Token refresh on submit** | **`getToken(true)`** reduces stale-session **401** |

---

## UX Rules

| Rule | Detail |
| --- | --- |
| **Cancel** | **`NuxtLink`** back to list — no unsaved guard (no draft autosave) |
| **Hints** | Show upload limits from **`upload-limits.ts`** under file inputs |
| **Create copy** | Explain Laravel stores files and saves CDN URLs on create |
| **Edit copy (sound)** | Explain replace uploads use Laravel Spaces pipeline |
| **Edit copy (cover)** | Document **`POST …/admin/uploads`** + optional URL paste |
| **Progress** | XHR progress bar during edit uploads only |
| **Retry** | User re-submits form or re-picks file — no automatic retry loop |
| **Access request** | Redirect with flash when **403** admin not approved |

**Explicitly excluded:** collaborative editing, autosave drafts, AI generation buttons, chunk upload UI.

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| **Client-only validation** | User reaches server **422** | Keep gates aligned with specs; friendly messages |
| **Pre-upload on create** | Double pipeline, partial failure states | **Single multipart POST** on create — enforced in forms |
| **Stale CDN URL in form** | PATCH clears or wrong URL | Upload response overwrites **`form.*_url`**; load **`initial`** on edit mount |
| **Forgotten blob URLs** | Memory leak | **`revokeObjectURL`** on unmount / re-pick |
| **413 masked as network error** | Confusing UX | **`friendlyLaravelUploadHttpError(413, …)`** |
| **Assuming upload success without `data.url`** | Broken preview | **`uploadAssetViaLaravel`** rejects invalid JSON |
| **Duplicate submit** | Double create | **`saving`** + **`canSubmit`** disable button |
| **Non-approved admin** | **403** on every write | Middleware + **`redirectToAccessRequestWithFlash`** |

---

## Validation

### Manual checklist (staging)

- [ ] Sound **create**: both files + metadata → **201** → redirect to edit with CDN URLs on entity
- [ ] Sound **edit**: replace audio → progress → **`file_url`** updates → **Save** → list
- [ ] Cover **create**: three images → **201** → list shows CDN URLs
- [ ] Cover **edit**: upload one slot OR paste URL → **Save** → **PATCH** persists
- [ ] **422** oversize file → friendly message with field name
- [ ] **403** non-approved → access-request redirect
- [ ] Submit disabled while **`saving`** or **`upload.uploading`**
- [ ] No **`DO_SPACES_*`** in browser env / network tab targets Spaces directly

### Code review gates

- [ ] New catalog form follows **page → component → composable → service** layers
- [ ] Create uses **single multipart** — not `/api/admin/uploads` first
- [ ] Errors use **`friendly*ApiMessage`** — not raw **`$fetch`** messages
- [ ] Responses normalized via **`unwrapOne`** / **`unwrapList`**
- [ ] CDN URLs from API only — no client key construction
- [ ] Upload limits imported from **`upload-limits.ts`** — not duplicated magic numbers

---

## Related Files

### Standards and specs

| Document | Path |
| --- | --- |
| **This standard** | `docs/standards/admin-form-patterns.md` |
| Upload validation | [`upload-validation.md`](upload-validation.md) |
| Form Request patterns | [`laravel-form-request-patterns.md`](laravel-form-request-patterns.md) |
| API Resource patterns | [`api-resource-patterns.md`](api-resource-patterns.md) |
| Auth (Firebase + sync) | [`front-vibes-auth-core.md`](front-vibes-auth-core.md) |
| Create sound spec | [`docs/specs/sounds/create-sound/spec.md`](../specs/sounds/create-sound/spec.md) |
| Create cover bundle spec | [`docs/specs/covers/create-cover-bundle/spec.md`](../specs/covers/create-cover-bundle/spec.md) |

### ixora-admin implementation

| File | Role |
| --- | --- |
| `components/SoundForm.vue` | Sound create/edit form reference |
| `components/CoverBundleForm.vue` | Cover bundle create/edit form reference |
| `composables/useSounds.ts` | Sound list + CRUD delegation |
| `composables/useCoverBundles.ts` | Cover list + CRUD delegation |
| `composables/useUpload.ts` | Edit-mode XHR uploads + progress |
| `composables/useFirebaseAuth.ts` | Token + Laravel sync |
| `composables/useLaravelAccessRedirect.ts` | 403 → access-request |
| `services/api/sound.service.ts` | Multipart create, PATCH, normalization |
| `services/api/cover-bundle.service.ts` | Multipart create, PATCH, normalization |
| `services/api/upload.service.ts` | **`uploadAssetViaLaravel`** XHR |
| `services/api/laravel-api-error.ts` | **`friendlySoundApiMessage`**, **`friendlyCoverBundleApiMessage`**, **`friendlyLaravelUploadHttpError`** |
| `shared/upload-limits.ts` | Client accept attributes and hint strings |
| `middleware/auth.ts` | Firebase + approved-admin route gate |
| `pages/sounds/create.vue`, `[id]/edit.vue` | Sound page wrappers |
| `pages/covers/create.vue`, `[id]/edit.vue` | Cover page wrappers |

When admin form behaviour changes, update **this file first**, then components/services, [`upload-validation.md`](upload-validation.md), and aligned feature specs.
