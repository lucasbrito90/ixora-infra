# Ixora Documentation

Central architecture, specifications, standards and engineering decisions for the Ixora ecosystem.

---

# Repositories

| Repository | Responsibility |
|---|---|
| back_vibes | Laravel API, business rules, uploads, queues |
| front_vibes | Ionic + Vue mobile application |
| ixora-admin | Nuxt admin panel |
| ixora-infra | OpenTofu infrastructure and central documentation |

---

# Documentation Structure

| Folder | Purpose |
|---|---|
| architecture/ | Technical architecture and platform-level design |
| specs/ | Feature specifications and implementation contracts |
| standards/ | Engineering standards and project rules |
| decisions/ | Architecture Decision Records (ADRs) |
| flows/ | Functional and operational flows |

---

# Architecture

## Mobile
- architecture/mobile/android-native-customizations.md

## Audio
- architecture/audio/audio-cache.md
- architecture/audio/audio-engine-fade-limitations.md
- architecture/audio/native-loop-fadein.md

## Storage
- architecture/storage/storage-strategy.md
- architecture/storage/artwork-background-strategy.md
- architecture/storage/mobile-cdn-validation.md

---

# Standards

- standards/git-flow.md
- standards/front-vibes-auth-core.md
- standards/front-vibes-ionic-routing.md

---

# Specifications

## Sounds
- specs/sounds/create-sound/

## Cover Bundles
- specs/covers/create-cover-bundle/

## Infra
- specs/infra/staging-digitalocean/

---

# Decisions (ADRs)

Planned architecture decisions:

- ADR-001 Laravel only writes to Spaces
- ADR-002 Mobile apps consume CDN URLs only
- ADR-003 Native audio engine over HTML Audio
- ADR-004 CapacitorHttp for offline downloads
- ADR-005 Loop fade-in temporarily disabled

---

# Engineering Principles

- Backend owns all business rules
- Laravel is the only asset writer
- Mobile/admin never receive Spaces credentials
- Assets are distributed through CDN URLs
- Uploads are validated server-side
- Audio playback prioritizes native APIs
- Specs drive implementation
- Infrastructure is fully reproducible through OpenTofu

---

# AI-assisted Development

Before implementing features with AI tools (Cursor, Codex, Claude, ChatGPT):

1. Read relevant architecture docs
2. Read related standards
3. Read feature specs
4. Follow ADR decisions
5. Avoid introducing conflicting architecture

The documentation in this repository is the source of truth for the Ixora ecosystem.