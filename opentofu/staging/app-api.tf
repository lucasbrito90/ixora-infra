locals {
  # Firebase discrete env vars (preferred over inline FIREBASE_SERVICE_ACCOUNT_JSON).
  api_firebase_discrete_ready = (
    trimspace(var.api_firebase_project_id) != "" &&
    trimspace(var.api_firebase_private_key) != "" &&
    trimspace(var.api_firebase_client_email) != ""
  )

  api_firebase_discrete_required_env = concat(
    [
      {
        key   = "FIREBASE_TYPE"
        type  = "GENERAL"
        value = trimspace(var.api_firebase_type) != "" ? var.api_firebase_type : "service_account"
      },
    ],
    [
      {
        key   = "FIREBASE_PROJECT_ID"
        type  = "SECRET"
        value = var.api_firebase_project_id
      },
      {
        key   = "FIREBASE_PRIVATE_KEY"
        type  = "SECRET"
        value = var.api_firebase_private_key
      },
      {
        key   = "FIREBASE_CLIENT_EMAIL"
        type  = "SECRET"
        value = var.api_firebase_client_email
      },
    ],
  )

  api_firebase_discrete_optional_env = concat(
    trimspace(var.api_firebase_private_key_id) != "" ? [{
      key   = "FIREBASE_PRIVATE_KEY_ID"
      type  = "SECRET"
      value = var.api_firebase_private_key_id
    }] : [],
    trimspace(var.api_firebase_token_uri) != "" ? [{
      key   = "FIREBASE_TOKEN_URI"
      type  = "SECRET"
      value = var.api_firebase_token_uri
    }] : [],
    trimspace(var.api_firebase_client_id) != "" ? [{
      key   = "FIREBASE_CLIENT_ID"
      type  = "SECRET"
      value = var.api_firebase_client_id
    }] : [],
    trimspace(var.api_firebase_auth_uri) != "" ? [{
      key   = "FIREBASE_AUTH_URI"
      type  = "SECRET"
      value = var.api_firebase_auth_uri
    }] : [],
    trimspace(var.api_firebase_auth_provider_x509_cert_url) != "" ? [{
      key   = "FIREBASE_AUTH_PROVIDER_X509_CERT_URL"
      type  = "SECRET"
      value = var.api_firebase_auth_provider_x509_cert_url
    }] : [],
    trimspace(var.api_firebase_client_x509_cert_url) != "" ? [{
      key   = "FIREBASE_CLIENT_X509_CERT_URL"
      type  = "SECRET"
      value = var.api_firebase_client_x509_cert_url
    }] : [],
  )

  api_firebase_discrete_runtime_env = local.api_firebase_discrete_ready ? concat(
    local.api_firebase_discrete_required_env,
    local.api_firebase_discrete_optional_env,
  ) : []

  # Browser CORS for Nuxt admin (Firebase Bearer; Laravel supports_credentials false). No * in origins.
  api_cors_allowed_origins_effective = trimspace(var.api_cors_allowed_origins) != "" ? var.api_cors_allowed_origins : join(",", [
    "https://${trimspace(var.admin_domain)}",
    "http://localhost:3000",
    "http://localhost:5173",
  ])

  # Shared RUN_TIME env for Laravel API (web) and queue worker — single source of truth.
  api_worker_runtime_env = concat(
    [
      { key = "APP_NAME", value = "Ixora", type = "GENERAL" },
      { key = "APP_ENV", value = "staging", type = "GENERAL" },
      { key = "APP_DEBUG", value = "false", type = "GENERAL" },
      { key = "APP_URL", value = "https://${var.api_domain}", type = "GENERAL" },
      { key = "CORS_ALLOWED_ORIGINS", value = local.api_cors_allowed_origins_effective, type = "GENERAL" },
      # Phase 8.8.8 (back_vibes) shipped OTLP log export via a "otel" Monolog
      # channel, documented in back_vibes/.env.example as intended for staging
      # ("Staging: stderr,otel" / "set to otlp in staging/production alongside
      # LOG_STACK=stderr,otel") — but this file was never updated to activate
      # it, so Loki stayed empty. "stack" fans out to both: stderr (unchanged,
      # still reaches DO Runtime Logs) and otel (OTLP export to Loki, uses the
      # OTEL_* env below).
      { key = "LOG_CHANNEL", value = "stack", type = "GENERAL" },
      { key = "LOG_STACK", value = "stderr,otel", type = "GENERAL" },
      { key = "QUEUE_CONNECTION", value = "database", type = "GENERAL" },
      { key = "PUSH_PROVIDER", value = "fcm", type = "GENERAL" },
      # FrankenPHP worker mode (TD-5, observability-foundation Phase 8.9): informational
      # today (no Swoole-only driver-conditional code reads this), but keeps
      # config('octane.server') consistent with the actual runtime driver
      # baked into docker/frankenphp/Caddyfile (back_vibes).
      { key = "OCTANE_SERVER", value = "frankenphp", type = "GENERAL" },
      # Laravel cache/session: avoid Postgres `cache` table (migration owner vs app DB user ACL on staging).
      # App Platform worker + api each get ephemeral local disk; staging accepts that trade-off vs DB/redis cache sharing.
      { key = "CACHE_STORE", value = "file", type = "GENERAL" },
      { key = "SESSION_DRIVER", value = "file", type = "GENERAL" },
      { key = "DB_CONNECTION", value = "pgsql", type = "GENERAL" },
      { key = "DB_HOST", value = digitalocean_database_cluster.postgres.private_host, type = "GENERAL" },
      { key = "DB_PORT", value = tostring(digitalocean_database_cluster.postgres.port), type = "GENERAL" },
      { key = "DB_SSLMODE", value = "require", type = "GENERAL" },
      { key = "DB_DATABASE", value = digitalocean_database_db.app.name, type = "GENERAL" },
      { key = "DB_USERNAME", value = digitalocean_database_user.app.name, type = "SECRET" },
      { key = "DB_PASSWORD", value = digitalocean_database_user.app.password, type = "SECRET" },
      { key = "DO_SPACES_BUCKET", value = var.spaces_bucket_name, type = "GENERAL" },
      { key = "DO_SPACES_REGION", value = var.spaces_region, type = "GENERAL" },
      { key = "DO_SPACES_ENDPOINT", value = "https://${var.spaces_region}.digitaloceanspaces.com", type = "GENERAL" },
      { key = "DO_SPACES_CDN_URL", value = "https://${local.spaces_cdn_host}", type = "GENERAL" },
    ],
    trimspace(var.api_do_spaces_key) != "" ? [{ key = "DO_SPACES_KEY", value = var.api_do_spaces_key, type = "SECRET" }] : [],
    trimspace(var.api_do_spaces_secret) != "" ? [{ key = "DO_SPACES_SECRET", value = var.api_do_spaces_secret, type = "SECRET" }] : [],
    trimspace(var.api_app_key) != "" ? [{ key = "APP_KEY", value = var.api_app_key, type = "SECRET" }] : [],
    local.api_firebase_discrete_runtime_env,
    trimspace(var.api_mail_password) != "" ? [{ key = "MAIL_PASSWORD", value = var.api_mail_password, type = "SECRET" }] : [],
    trimspace(var.admin_access_review_email) != "" ? [{ key = "ADMIN_ACCESS_REVIEW_EMAIL", value = var.admin_access_review_email, type = "GENERAL" }] : [],
    [for k, v in var.api_env_general : { key = k, value = v, type = "GENERAL" }],
    [for k in nonsensitive(keys(var.api_secrets_extra)) : { key = k, value = var.api_secrets_extra[k], type = "SECRET" }],
  )
}

resource "digitalocean_app" "api" {
  spec {
    name   = local.api_app_name
    region = local.app_region

    domain {
      name = var.api_domain
      type = "PRIMARY"
    }

    vpc {
      id = digitalocean_vpc.staging.id
    }

    service {
      name               = "api"
      instance_count     = 1
      instance_size_slug = "basic-xxs"

      http_port = var.api_http_port

      github {
        repo           = var.github_repo_api
        branch         = var.github_branch
        deploy_on_push = true
      }

      dockerfile_path = var.api_dockerfile_path
      source_dir      = var.api_source_dir

      dynamic "env" {
        for_each = { for idx, e in local.api_worker_runtime_env : idx => e }
        content {
          key   = env.value.key
          value = env.value.value
          type  = env.value.type
          scope = "RUN_TIME"
        }
      }
    }

    # Background queue: App Platform **worker** (not a service) — no HTTP port, not ingress-routable.
    # VPC is configured on `spec` above and applies to the whole app; env matches `api` via locals.
    worker {
      name               = "queue"
      instance_count     = 1
      instance_size_slug = "basic-xxs"

      github {
        repo           = var.github_repo_api
        branch         = var.github_branch
        deploy_on_push = true
      }

      dockerfile_path = var.api_dockerfile_path
      source_dir      = var.api_source_dir

      run_command = "php artisan queue:work --queue=push,smart-home,default --tries=3 --sleep=3 --timeout=90"

      dynamic "env" {
        for_each = { for idx, e in local.api_worker_runtime_env : idx => e }
        content {
          key   = env.value.key
          value = env.value.value
          type  = env.value.type
          scope = "RUN_TIME"
        }
      }
    }

    # Scheduler dispatcher worker: App Platform **worker** component.
    #
    # Runs `php artisan schedules:dispatch-loop` as a long-running process.
    # The loop command calls `schedules:dispatch-due` every ~60 seconds internally,
    # giving reliable minute-granularity dispatch without relying on DO App Platform
    # Scheduled Jobs, which are:
    #   - Not fully supported by the digitalocean/digitalocean provider v2.87.0
    #     (SCHEDULED kind / cron_expression missing — issue #1529).
    #   - Subject to a 15-minute minimum cadence on the DO platform.
    #
    # Idempotency is guaranteed by occurrence_key (ADR-010): if the worker restarts
    # or two instances briefly overlap, duplicate dispatch attempts are silently
    # skipped via the unique (schedule_id, occurrence_key) DB index.
    #
    # Same Docker image, source, and RUN_TIME env as `api` / `queue`.
    worker {
      name               = "scheduler"
      instance_count     = 1
      instance_size_slug = "basic-xxs"

      github {
        repo           = var.github_repo_api
        branch         = var.github_branch
        deploy_on_push = true
      }

      dockerfile_path = var.api_dockerfile_path
      source_dir      = var.api_source_dir

      run_command = "php artisan schedules:dispatch-loop"

      dynamic "env" {
        for_each = { for idx, e in local.api_worker_runtime_env : idx => e }
        content {
          key   = env.value.key
          value = env.value.value
          type  = env.value.type
          scope = "RUN_TIME"
        }
      }
    }

    ingress {
      rule {
        component {
          name = "api"
        }
        match {
          path {
            prefix = "/"
          }
        }
      }
    }
  }

  depends_on = [
    digitalocean_database_cluster.postgres,
    digitalocean_database_user.app,
    digitalocean_vpc.staging,
  ]
}
