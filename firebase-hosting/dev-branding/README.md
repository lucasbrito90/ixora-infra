# Dev branding pages (Firebase Hosting)

Minimal homepage + privacy policy for the `app-vibes-dev` Firebase project, published to satisfy Google OAuth Branding verification requirements for the Google Home APIs OAuth client used by the GH02 spike (v1.6.0 — see `ixora-infra/docs/specs/smart-home/google-home/`).

- Homepage: https://app-vibes-dev.firebaseapp.com/
- Privacy Policy: https://app-vibes-dev.firebaseapp.com/privacy

## Scope

Development-only. Not the production IXORA marketing site or privacy policy. Content is deliberately minimal and factual — it describes only what the codebase actually does today, grounded in `back_vibes` models/migrations and the ADRs cited inline in `public/privacy/index.html`. It does not claim any Google Home behavior beyond what ADR-036 / GH03a / GH03b actually establish, and it is marked `noindex` (see `firebase.json` headers) since it is not meant to be discovered by search engines.

## Deploy

```bash
firebase deploy --project app-vibes-dev --only hosting -c firebase-hosting/dev-branding/firebase.json
```

Deployed from `ixora-infra` deliberately — this is hosting/deployment configuration, not application code, and no existing repo (`back_vibes`, `front_vibes`, `ixora-admin`) owns a public marketing/legal site today.
