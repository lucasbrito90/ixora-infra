# ixora-infra

Infrastructure-as-code for **Ixora**.

## OpenTofu / Terraform

- **Staging (DigitalOcean):** [`opentofu/staging/`](opentofu/staging/README.md) — VPC, managed Postgres, Spaces, App Platform (Laravel API + Nuxt admin). Laravel Firebase credentials on staging are wired as discrete `api_firebase_*` env vars mapped to Laravel `FIREBASE_*`.

See each stack’s `README.md` for prerequisites, `tofu init` / `plan` / `apply`, and security notes.
