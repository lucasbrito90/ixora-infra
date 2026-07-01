# ── DigitalOcean API ──────────────────────────────────────────────────────────

variable "do_token" {
  description = "DigitalOcean API token (personal access token). Set via TF_VAR_do_token or CI secret."
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = "Spaces access key ID (for bucket management only). Required if creating Spaces bucket."
  type        = string
  sensitive   = true
  default     = ""
}

variable "spaces_secret_key" {
  description = "Spaces secret key. Required if creating Spaces bucket."
  type        = string
  sensitive   = true
  default     = ""
}

variable "manage_spaces_bucket" {
  description = "If false, skips Spaces bucket resource (e.g. bucket already exists). Provider still needs valid Spaces keys when true."
  type        = bool
  default     = true
}

# ── GitHub (App Platform source) ─────────────────────────────────────────────

variable "github_repo_api" {
  description = "Laravel API repo in owner/name form (e.g. myorg/back_vibes)."
  type        = string
}

variable "github_repo_admin" {
  description = "Nuxt Admin repo in owner/name form (e.g. myorg/ixora-admin)."
  type        = string
}

variable "github_branch" {
  description = "Branch deployed to staging App Platform apps."
  type        = string
  default     = "staging"
}

# ── Networking / domains ──────────────────────────────────────────────────────

variable "api_domain" {
  description = "Custom hostname for the Laravel API (must match APP_URL host)."
  type        = string
  default     = "staging-api.ixora-app.app"
}

variable "admin_domain" {
  description = "Custom hostname for Nuxt static admin."
  type        = string
  default     = "staging-admin.ixora-app.app"
}

variable "api_cors_allowed_origins" {
  description = "Comma-separated Laravel CORS_ALLOWED_ORIGINS (explicit URLs only, no *). Empty defaults to https://{admin_domain},http://localhost:3000,http://localhost:5173."
  type        = string
  default     = ""
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

variable "db_cluster_name" {
  description = "Managed Postgres cluster name."
  type        = string
  default     = "ixora-staging-postgres"
}

variable "db_node_size" {
  description = "Smallest practical slug for staging (cost-aware). Check DO docs for current slugs in tor1."
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "db_pg_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_node_count" {
  description = "Single node for staging cost control."
  type        = number
  default     = 1
}

variable "db_firewall_extra_ip_addrs" {
  description = "Additional Postgres firewall ip_addr rules beyond the staging VPC CIDR (e.g. developer/ops public IP for direct psql). Empty strings are ignored."
  type        = list(string)
  default     = ["108.180.255.58"]
}

# ── Spaces ────────────────────────────────────────────────────────────────────

variable "spaces_bucket_name" {
  description = "Globally unique Spaces bucket name (must be unique across all DO accounts)."
  type        = string
  default     = "ixora-buckets"
}

variable "spaces_region" {
  description = "Spaces region slug (Toronto)."
  type        = string
  default     = "tor1"
}

# ── Laravel API — non-secret env (override via tfvars example pattern) ──────

variable "api_env_general" {
  description = "Additional GENERAL env vars for the API service (RUN_TIME). Do not put secrets here."
  type        = map(string)
  default     = {}
}

# ── Laravel API — secrets & sensitive runtime config ──────────────────────────

variable "api_app_key" {
  description = "APP_KEY for Laravel (base64 key). SECRET."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_type" {
  description = "Laravel FIREBASE_TYPE (usually service_account). Empty → Laravel resolves default service_account in code."
  type        = string
  default     = ""
}

variable "api_firebase_project_id" {
  description = "FIREBASE_PROJECT_ID (GCP project)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_private_key_id" {
  description = "FIREBASE_PRIVATE_KEY_ID."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_private_key" {
  description = "FIREBASE_PRIVATE_KEY — PEM multi-line acceptable; often stored with \\n escapes in Terraform/DO."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_token_uri" {
  description = "FIREBASE_TOKEN_URI (omit for Google defaults in Laravel resolver)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_client_email" {
  description = "FIREBASE_CLIENT_EMAIL."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_client_id" {
  description = "FIREBASE_CLIENT_ID."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_auth_uri" {
  description = "FIREBASE_AUTH_URI (omit for Google defaults in Laravel resolver)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_auth_provider_x509_cert_url" {
  description = "FIREBASE_AUTH_PROVIDER_X509_CERT_URL (omit for Google defaults in Laravel resolver)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_firebase_client_x509_cert_url" {
  description = "FIREBASE_CLIENT_X509_CERT_URL."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_mail_password" {
  description = "SMTP / mail password if applicable. SECRET."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_secrets_extra" {
  description = "Additional SECRET key/value pairs for the API (merged at RUN_TIME)."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "api_do_spaces_key" {
  description = "DO Spaces S3 key used by Laravel at runtime (not the Terraform Spaces keys). SECRET."
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_do_spaces_secret" {
  description = "DO Spaces secret used by Laravel at runtime. SECRET."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Nuxt Admin — build-time public env ──────────────────────────────────────

variable "nuxt_public_api_base_url" {
  description = "NUXT_PUBLIC_API_BASE_URL for generate build."
  type        = string
  default     = "https://staging-api.ixora-app.app/api"
}

variable "nuxt_public_firebase_api_key" {
  description = "NUXT_PUBLIC_FIREBASE_API_KEY (public client key; safe in repo but keep out of tfvars examples with real projects if you prefer)."
  type        = string
  default     = ""
}

variable "nuxt_public_firebase_auth_domain" {
  description = "NUXT_PUBLIC_FIREBASE_AUTH_DOMAIN"
  type        = string
  default     = ""
}

variable "nuxt_public_firebase_project_id" {
  description = "NUXT_PUBLIC_FIREBASE_PROJECT_ID"
  type        = string
  default     = ""
}

variable "nuxt_public_firebase_storage_bucket" {
  description = "NUXT_PUBLIC_FIREBASE_STORAGE_BUCKET"
  type        = string
  default     = ""
}

variable "nuxt_public_firebase_messaging_sender_id" {
  description = "NUXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID"
  type        = string
  default     = ""
}

variable "nuxt_public_firebase_app_id" {
  description = "NUXT_PUBLIC_FIREBASE_APP_ID"
  type        = string
  default     = ""
}

variable "admin_access_review_email" {
  description = "ADMIN_ACCESS_REVIEW_EMAIL for Laravel (non-secret)."
  type        = string
  default     = ""
}

variable "api_http_port" {
  description = "HTTP port exposed by the Laravel container (must match Dockerfile)."
  type        = number
  default     = 8080
}

variable "api_dockerfile_path" {
  description = "Path to Dockerfile relative to repository root."
  type        = string
  default     = "Dockerfile"
}

variable "api_source_dir" {
  description = "Build context directory within the repo (App Platform)."
  type        = string
  default     = "/"
}
