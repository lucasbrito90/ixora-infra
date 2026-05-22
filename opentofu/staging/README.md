# Ixora — staging infrastructure (OpenTofu / Terraform)

Declarative **staging** footprint on **DigitalOcean** (Toronto `tor1` / App Platform `tor`):

| Component | Implementation |
|-----------|----------------|
| VPC | `digitalocean_vpc` |
| PostgreSQL | Managed cluster in VPC, **no Droplets** |
| Spaces | Private ACL bucket (optional via `manage_spaces_bucket`) |
| Laravel API | App Platform **service** `api` (web) + **worker** `queue` (`queue:work`, same image/env) |
| Nuxt Admin | App Platform **static site** (`npm run generate`) |
| Custom domains | Declared on apps; DNS steps documented |

**No secrets belong in git.** Use `terraform.tfvars.example` as a template only; real values live in untracked `terraform.tfvars`, CI variables, or `TF_VAR_*`.

---

## Prerequisites

- DigitalOcean account with billing enabled.
- **API token** with write access (Apps, Databases, Networking, Spaces).
- **Spaces keys** (Spaces access key + secret) **only if** OpenTofu manages the bucket (`manage_spaces_bucket = true`). These are **separate** from `do_token` (S3-compatible API).
- GitHub repositories reachable by DigitalOcean App Platform (authorize the DO GitHub app / deploy keys as required in the DO UI).
- Laravel repo contains a **`Dockerfile`** suitable for App Platform (default path `Dockerfile`, port defaults to **8080** — override `api_http_port` / `api_dockerfile_path` if needed).
- Nuxt repo supports **`npm ci && npm run generate`** and writes static output to **`.output/public`**.

---

## Install OpenTofu

See [OpenTofu install docs](https://opentofu.org/docs/intro/install/). Terraform CLI (`terraform >= 1.6`) is largely compatible if you replace `tofu` with `terraform`.

---

## Configure credentials

```bash
export TF_VAR_do_token="dop_v1_..."           # or use terraform.tfvars (gitignored)
export TF_VAR_spaces_access_id="..."          # if managing Spaces bucket
export TF_VAR_spaces_secret_key="..."
```

OpenTofu does **not** read `DIGITALOCEAN_TOKEN` automatically for this stack — the provider uses `var.do_token`.

---

## Usage

```bash
cd opentofu/staging
cp terraform.tfvars.example terraform.tfvars   # edit locally; never commit
tofu init
tofu plan
tofu apply
```

### Lock file (`.terraform.lock.hcl`)

**Commit `.terraform.lock.hcl`** after `tofu init` so everyone uses the same provider versions. It is **not** ignored by `.gitignore`.

---

## Security notes

- **No Droplets** are defined.
- Postgres sits in a **VPC**; runtime DB connections use **`private_host`** from the cluster.
- **`digitalocean_database_firewall`** allows only **`digitalocean_vpc.staging.ip_range`** (private CIDR — not `0.0.0.0/0`). Apps must still use **`private_host`**; there is no public DB exposure from this rule alone.
- Spaces bucket uses **`acl = "private"`**. Laravel still needs **runtime** Spaces keys (`DO_SPACES_*`) passed as App secrets — those are **not** stored in this repo.
- App env secrets use App Platform **SECRET** types where appropriate; OpenTofu may still show perpetual drift for encrypted values — see [provider discussion](https://github.com/digitalocean/terraform-provider-digitalocean/issues/869).

---

## Cost notes (indicative)

Staging is sized for **low cost**, not HA:

- Single-node Postgres (`db_node_size`, default `db-s-1vcpu-1gb`).
- API **web** + **`queue` worker** each use a **`basic-xxs`** component (worker has no public HTTP port).
- Static site pricing is modest vs always-on containers.

Check current DigitalOcean pricing pages — amounts change.

---

## What is **not** automated yet

- **GitHub ↔ DO** authorization (first deploy often needs UI confirmation).
- **DNS records** at your registrar unless you uncomment/adapt examples in `domains.tf`.
- **SSL** for custom domains: App Platform provisions certs after DNS validates.
- **Bucket CDN / CORS** toggles — only the private bucket + example CDN hostname output are scaffolded.
- **Migrations / APP_KEY rotation / Spaces key rotation** — operational tasks outside IaC.
- **Firewall**: DB trusted source is the **staging VPC CIDR** (`ip_addr` rule); cluster lives in that VPC. Adjust if you peer additional VPCs and need DB access from them.

---

## Files

| File | Role |
|------|------|
| `providers.tf` | Provider pin + DO + Spaces credentials |
| `variables.tf` | Inputs (secrets as sensitive vars) |
| `main.tf` | Shared locals |
| `vpc.tf` | VPC |
| `database.tf` | Postgres + firewall |
| `spaces.tf` | Spaces bucket |
| `app-api.tf` | Laravel App Platform |
| `app-admin.tf` | Nuxt static site |
| `domains.tf` | DNS notes / optional patterns |
| `outputs.tf` | Hostnames, IDs, sensitive DB password |
| `terraform.tfvars.example` | Safe placeholders only |

---

## Assumptions & manual next steps

1. Confirm **`basic-xxs`** and **`db-s-1vcpu-1gb`** exist in Toronto; bump sizes if builds fail OOM.
2. Align **`api_http_port`** with your Dockerfile `EXPOSE`.
3. Set **all required secrets** (`APP_KEY`, Firebase JSON, mail, Laravel Spaces keys) via `TF_VAR_*` or untracked tfvars before first deploy.
4. Complete **custom domain DNS** using `tofu output api_live_url` / `admin_live_url` targets from DO.
5. **Bucket name** must be globally unique — adjust `spaces_bucket_name` if taken.
