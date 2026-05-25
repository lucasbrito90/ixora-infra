# Apply Cover Bundle — apply catalog visuals to vibe form

**Status:** Active feature specification (source of truth)  
**Version:** 2.0 (consolidated; matches current `front_vibes` client apply flow)  
**Feature ID:** `vibes/apply-cover-bundle`  
**Platform:** Mobile form flow (`front_vibes` create/edit only)

---

## Goal

Enable an **authenticated mobile user** on **Create Vibe** or **Edit Vibe** to **apply an existing catalog cover bundle** to **local vibe form state**: merge **non-empty** bundle CDN URL strings into **`thumbnail_url`**, **`artwork_url`**, and **`player_background_url`**, preview the result immediately, and persist copied strings on the vibe row only when the user **submits** create/update — **without** mutating the cover bundle catalog, **without** uploads, and **without** linking the vibe to a bundle via FK.

**Success criteria:**

- **`applyCoverBundleToFormFields`** is the **single** merge implementation.
- **Non-empty** bundle URL → **overwrite** matching form field; **empty** bundle URL → **preserve** existing form value.
- **Apply** updates **unsaved form state only** — no API write on Apply tap.
- After vibe save, the **vibe owns copied HTTPS URL strings** (no **`cover_bundle_id`**).
- Previews use **`vibe-form-preview.ts`** + **`artwork.ts`** fallback chains (URLs → gradients).
- **Not** the admin catalog create spec — see [`create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md).

---

## Scope

### In scope

- **Client-side merge:** **`applyCoverBundleToFormFields(form, bundle)`**
- **Picker UI:** **`CoverBundlePickerModal`** — **`GET /api/cover-bundles`**, select, emit **`apply`**
- **Integration:** **`CreateVibePage`**, **`EditVibePage`** — same apply + preview pattern
- **Unsaved form state** — apply mutates reactive form until submit or navigation away
- **Pre-save previews** — **`vibePreviewFromImageFields`** + **`artwork.ts`** helpers
- **Persist on save** — **`POST /api/vibes`** / **`PATCH /api/vibes/{id}`** send three URL keys (separate save specs)
- **Read-only catalog input** — bundles loaded for picker only

### Out of scope

- **Creating cover bundles** — admin multipart create ([`create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md))
- **Editing catalog bundle rows** — admin PATCH / replace uploads
- **Upload / replace images on apply** — no bytes uploaded from mobile
- **Image editing, cropping, transformations**
- **Persistent bundle link** — no **`cover_bundle_id`** on user vibes, no “linked bundle” UI
- **Preset `cover_bundle_id`** — admin preset editor (FK on **`preset_vibes`**)
- **Preset import** — server copies URLs in **`PresetVibeController::import`** (not form apply)
- **`vibe_sounds`** — unchanged by cover apply
- **Post-save list/player imagery** — uses saved vibe URLs via same **`artwork.ts`** helpers (not live bundle fetch)

---

## Actors

| Actor | Role |
| --- | --- |
| **End user** | Opens picker, selects bundle, taps Apply, then saves vibe form. |
| **`CoverBundlePickerModal`** | Loads catalog list; emits selected **`CoverBundle`** to parent. |
| **`applyCoverBundleToFormFields`** | Pure merge into form reactive object. |
| **Create / Edit vibe pages** | Own form state, previews, and save submit. |
| **`useCoverBundles`** | **`GET /api/cover-bundles`** with Firebase Bearer. |
| **`artwork.ts` / `vibe-form-preview.ts`** | Preview resolution and gradient fallbacks. |
| **Cover bundle catalog** | Read-only URL source — **unchanged** by apply. |
| **Laravel (on save only)** | Persists vibe URL columns when whitelisted — see [`create-vibe/spec.md`](../create-vibe/spec.md) / [`update-vibe/spec.md`](../update-vibe/spec.md). |

---

## User Journey

### Shared apply path (create and edit)

1. User opens **Create Vibe** (`/vibes/create`) or **Edit Vibe** (`/vibes/:id/edit`).
2. Form shows metadata + **Cover visuals** block with three preview tiles (card · artwork · player strip).
3. User taps **Choose cover** → **`CoverBundlePickerModal`** opens.
4. Modal calls **`GET /api/cover-bundles`** (on open); user selects a bundle card.
5. User taps **Apply** → modal emits **`apply`** with full **`CoverBundle`** → closes.
6. Parent **`onCoverApplied(bundle)`** calls **`applyCoverBundleToFormFields(form, bundle)`**.
7. Previews re-render from **local form fields** (no save yet).
8. User taps **Create Vibe** or **Save Changes** → JSON submit with visual URL fields.

### Create vs update after apply

| Step | **Create** (`CreateVibePage`) | **Update** (`EditVibePage`) |
| --- | --- | --- |
| Initial form visuals | Empty strings | Hydrated from **`GET /api/vibes/{id}`** (`watch selectedVibe`) |
| Apply | Merges bundle into empty or partial form | Merges bundle; **preserves** form slots where bundle URL empty |
| Submit | **`POST /api/vibes`** → **`router.replace('/vibes')`** | **`PATCH /api/vibes/{id}`** → **`router.replace('/vibes')`** |
| Unsaved apply | Lost if user navigates back without submit | Lost if user navigates back without submit |

**Not in journey:** admin bundle CRUD, preset import, sound attach, upload flows.

---

## Related Domain Model

```
cover_bundles (catalog)              vibes form (client, unsaved)
  thumbnail_url                           thumbnail_url
  artwork_url          applyCoverBundle    artwork_url
  player_background_url  ToFormFields      player_background_url
        │                    │                      │
        │                    │ (no API on Apply)    │
        │ unchanged          └──────────────────────┘
        │                              │
        │                              │ POST / PATCH (save)
        └──────────────────────────────┼──► vibes row (copied URL strings)
                                       └── no cover_bundle_id FK
```

| Concept | Apply behaviour |
| --- | --- |
| **`cover_bundles`** | **Read-only** — list for picker; row **not modified** on apply |
| **Form state** | **Mutated in memory** on Apply — authoritative for previews until save |
| **`vibes` row (after save)** | **Owns copied URL strings** — independent snapshot until user edits again |
| **`cover_bundle_id`** | **Not used** on user vibes |

Admin changing a bundle catalog row **does not** update saved vibes until the user re-applies or edits URLs manually.

---

## Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-1 | **`applyCoverBundleToFormFields`** is the **only** function that merges bundle → vibe form visual fields. |
| FR-2 | Mapped fields: **`thumbnail_url`**, **`artwork_url`**, **`player_background_url`**. |
| FR-3 | For each field: copy bundle value **only if `trim()` is non-empty** → **overwrite** form field. |
| FR-4 | Empty, null, or whitespace-only bundle value → **do not change** existing form field. |
| FR-5 | Apply runs **synchronously** on client — **no** HTTP request on Apply tap. |
| FR-6 | **`CoverBundlePickerModal`** loads bundles via **`GET /api/cover-bundles`** when opened. |
| FR-7 | Modal **Apply** disabled until a bundle is selected (`selectedId != null`). |
| FR-8 | Apply **does not** set **`card_image_url`** on form — previews use **`thumbnail_url`** via **`getVibeCardImageUrl`**. |
| FR-9 | Pre-save previews use **`vibePreviewFromImageFields(form fields)`** + **`artwork.ts`**. |
| FR-10 | **No uploads** — apply copies **opaque HTTPS CDN strings** only. |
| FR-11 | **No direct Spaces access** — no credentials, presigned URLs, or bucket SDK. |
| FR-12 | **Create** and **Edit** pages share the same apply helper and modal pattern. |
| FR-13 | Save submit sends trimmed URL strings or **`null`** when empty — persistence governed by vibe create/update specs. |
| FR-14 | Apply **does not** modify **`vibe_sounds`** or sound layers. |
| FR-15 | Bundle catalog row **remains unchanged** after apply and after vibe save. |

---

## Validation Rules

### Client — apply merge (authoritative for apply)

| Rule | Detail |
| --- | --- |
| Bundle field trim | Leading/trailing whitespace stripped before empty check |
| Overwrite | Non-empty after trim → assign to form field |
| Preserve | Empty after trim → form field untouched |
| Form field types | Reactive **strings** on create/edit (`''` default; edit hydrates from vibe) |
| Re-apply | User may apply another bundle — each slot overwritten only when new bundle supplies non-empty URL |

### Client — save payload (after apply)

| Field | Submit shape |
| --- | --- |
| `thumbnail_url` | `form.thumbnail_url.trim() \|\| null` |
| `artwork_url` | `form.artwork_url.trim() \|\| null` |
| `player_background_url` | `form.player_background_url.trim() \|\| null` |

### Server — persistence (cross-reference, not apply logic)

Laravel **`StoreVibeRequest` / `UpdateVibeRequest`** currently whitelist only metadata fields — visual URLs may be **silently dropped** on save until rules are added. Documented in [`create-vibe/spec.md`](../create-vibe/spec.md) and [`artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md). **Apply semantics are correct client-side regardless; save persistence is a separate alignment item.**

---

## Apply Semantics

### Implementation (`cover-bundle-apply.ts`)

```typescript
export function applyCoverBundleToFormFields(
  form: { thumbnail_url: string; artwork_url: string; player_background_url: string },
  bundle: CoverBundle,
): void {
  const t = bundle.thumbnail_url?.trim();
  if (t) form.thumbnail_url = t;
  const a = bundle.artwork_url?.trim();
  if (a) form.artwork_url = a;
  const p = bundle.player_background_url?.trim();
  if (p) form.player_background_url = p;
}
```

### Field mapping

| Form field | Bundle source | On apply |
| --- | --- | --- |
| `thumbnail_url` | `bundle.thumbnail_url` | Overwrite if non-empty after trim |
| `artwork_url` | `bundle.artwork_url` | Overwrite if non-empty after trim |
| `player_background_url` | `bundle.player_background_url` | Overwrite if non-empty after trim |

### Overwrite vs preserve — examples

| Form before | Bundle URLs | Form after |
| --- | --- | --- |
| all empty | all three set | all three copied |
| `thumbnail_url = A` | bundle `thumbnail_url` empty | `thumbnail_url` stays **A** |
| `artwork_url = X` | bundle `artwork_url = B` | `artwork_url = **B**` |
| partial bundle (thumbnail only) | thumbnail set, others empty | only thumbnail overwritten |

### Two-phase lifecycle

| Phase | When | Effect |
| --- | --- | --- |
| **1. Apply (client)** | User taps Apply in modal | Form + previews update; **catalog unchanged** |
| **2. Save (API)** | User submits create/edit | Vibe row updated with form URL strings; still **no bundle FK** |

### Unsaved form state

- Apply changes exist **only in memory** until successful save.
- Navigating **back** without submit **discards** applied URLs (create) or reverts to last fetched vibe on re-entry (edit).
- Modal close without Apply **does not** merge.

### Preview pipeline (pre-save)

```
form.thumbnail_url, artwork_url, player_background_url
        │
        ▼
vibePreviewFromImageFields({ ... })  →  minimal Vibe-shaped object (id: 0)
        │
        ▼
artwork.ts helpers on draft object
```

| Preview tile | Helper | URL priority | If no URL |
| --- | --- | --- | --- |
| **Card** (square) | `getVibeCardBackgroundStyle` | `card_image_url` → `thumbnail_url` | **`VIBE_ARTWORK_GRADIENTS`** (seed from draft `id` 0) |
| **Artwork** (square img) | `getVibeArtworkUrl` | `artwork_url` → `thumbnail_url` | hidden / empty img |
| **Player strip** | `getVibePlayerBackgroundStyle` | `player_background_url` → `thumbnail_url` | gradient |

**Note:** Draft preview sets **`card_image_url: null`** — card preview falls back to **`thumbnail_url`**, matching post-save **`VibeResource`** behaviour (`card_image_url ?? thumbnail_url`).

### Picker grid preview (`CoverBundlePickerModal`)

Bundle cards use **`previewSrc(b)`** = `b.thumbnail_url?.trim() || b.artwork_url?.trim() || null` — independent of apply merge rules (catalog display only).

---

## Mobile UX Rules

| Rule | Detail |
| --- | --- |
| Entry | **Choose cover** outline button on create/edit form |
| Modal title | **Choose a cover** |
| Hint (modal) | *Pick a catalog cover bundle. Only URLs provided by the bundle overwrite your vibe images.* |
| Hint (form) | *Card · artwork · player strip previews. Bundle applies only non-empty image URLs.* |
| Loading | **`AppLoadingState`** while **`GET /api/cover-bundles`** |
| Empty catalog | **`AppEmptyState`** — no active bundles |
| Error | **`AppErrorState`** with retry |
| Selection | Grid cards; selected state border highlight |
| Apply button | Block footer; disabled until selection |
| Post-apply | Modal closes; form previews update immediately |
| Save required | Apply alone does **not** persist — user must submit form |
| Create page | **`CreateVibePage.vue`** — `/vibes/create` |
| Edit page | **`EditVibePage.vue`** — `/vibes/:id/edit` |
| Components | **`CoverBundlePickerModal.vue`**, **`useCoverBundles`** composable |

---

## Storage / CDN Rules

| Rule | Detail |
| --- | --- |
| Apply operation | **Zero bytes transferred** for apply itself — only string copy in JS |
| URL shape | **Opaque HTTPS strings** from API (Spaces CDN, legacy Firebase, etc.) |
| No host whitelist | App treats URLs as opaque — [`mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| No Spaces SDK | Mobile never holds **`DO_SPACES_*`** |
| Shared objects | Copied vibe URLs may equal bundle CDN URLs — same underlying object |
| Catalog writer | **Laravel admin only** — bundle bytes uploaded at create ([`create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md)) |
| After save | **`vibes`** URL columns are source of truth for that user’s imagery |
| Safe delete (consequence) | Admin **`DELETE /api/cover-bundles/{id}`** may **409** when vibe columns still equal bundle URL strings — [`storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |

Apply **does not** create Spaces objects, presigned URLs, or new CDN paths.

---

## Failure Cases

| Case | Expected behaviour |
| --- | --- |
| Cover list load fails | Modal error state + retry; apply unavailable |
| No active bundles | Empty state in picker |
| User selects but closes modal | No merge — form unchanged |
| User applies but does not save | Previews show applied URLs; **lost on navigate away** (create) or discarded unsaved edits (edit) |
| Partial bundle (missing slot URLs) | Only non-empty bundle slots overwrite; others preserved |
| Re-apply different bundle | Per-slot overwrite rules apply again on current form state |
| Broken CDN URL in bundle | Preview `<img>` / CSS may fail to load — no client-side URL validation on apply |
| Save without Laravel URL whitelist | Metadata saves; URLs may not persist — **known server gap** |
| CDN object removed externally | Broken images after save — operational, not apply logic |

---

## Security Rules

| Rule | Requirement |
| --- | --- |
| Bundle list | **`GET /api/cover-bundles`** requires Firebase Bearer — [`front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| Apply tap | **No API call** — no new attack surface on apply action |
| Catalog mutation | End users **cannot** create/edit/delete bundles via apply flow |
| Vibe save | Owner-only **`PATCH`**; **`user_id`** not client-controlled |
| URL strings | Treated as display URLs only — no bucket credentials embedded |
| Secrets | **No `DO_SPACES_*`** in mobile bundle or env |

---

## Future Considerations

| Topic | Notes |
| --- | --- |
| Laravel URL whitelist | Unblocks persistence after apply — maintenance item |
| **`card_image_url` fourth slot** | Would need form + apply mapping change |
| Clear-form / reset visuals | Not shipped — user re-applies or edits manually |
| Admin web apply | Out of scope — mobile-only today |
| Fork URLs to vibe-scoped keys | Would require upload ADR — **not current** |

**Explicitly excluded:** upload replacement, image editing, cropping, transformations, persistent bundle links, collaborative vibes.

---

## Related Docs

| Document | Path |
| --- | --- |
| **This spec** | `docs/specs/vibes/apply-cover-bundle/spec.md` |
| Create cover bundle (catalog) | [`../../covers/create-cover-bundle/spec.md`](../../covers/create-cover-bundle/spec.md) |
| Create vibe | [`../create-vibe/spec.md`](../create-vibe/spec.md) |
| Update vibe | [`../update-vibe/spec.md`](../update-vibe/spec.md) |
| Artwork / background strategy | [`docs/architecture/storage/artwork-background-strategy.md`](../../../architecture/storage/artwork-background-strategy.md) |
| Storage policy | [`docs/architecture/storage/storage-strategy.md`](../../../architecture/storage/storage-strategy.md) |
| Mobile CDN QA | [`docs/architecture/storage/mobile-cdn-validation.md`](../../../architecture/storage/mobile-cdn-validation.md) |
| Auth | [`docs/standards/front-vibes-auth-core.md`](../../../standards/front-vibes-auth-core.md) |
| **front_vibes** | `src/utils/cover-bundle-apply.ts` |
| | `src/components/CoverBundlePickerModal.vue` |
| | `src/views/CreateVibePage.vue`, `src/views/EditVibePage.vue` |
| | `src/utils/artwork.ts`, `src/utils/vibe-form-preview.ts` |
| | `src/composables/useCoverBundles.ts` |

When apply behaviour changes, update **this file first**, then **`cover-bundle-apply.ts`**, create/edit pages, and architecture docs.
