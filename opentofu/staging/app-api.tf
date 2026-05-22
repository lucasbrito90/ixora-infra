locals {
  # Shared RUN_TIME env for Laravel API (web) and queue worker — single source of truth.
  api_worker_runtime_env = concat(
    [
      { key = "APP_NAME", value = "Ixora", type = "GENERAL" },
      { key = "APP_ENV", value = "staging", type = "GENERAL" },
      { key = "APP_DEBUG", value = "false", type = "GENERAL" },
      { key = "APP_URL", value = "https://${var.api_domain}", type = "GENERAL" },
      { key = "LOG_CHANNEL", value = "stderr", type = "GENERAL" },
      { key = "QUEUE_CONNECTION", value = "database", type = "GENERAL" },
      { key = "DB_CONNECTION", value = "pgsql", type = "GENERAL" },
      { key = "DB_HOST", value = digitalocean_database_cluster.postgres.private_host, type = "GENERAL" },
      { key = "DB_PORT", value = tostring(digitalocean_database_cluster.postgres.port), type = "GENERAL" },
      { key = "DB_SSLMODE", value = "require", type = "GENERAL" },
      { key = "DB_DATABASE", value = "defaultdb", type = "GENERAL" },
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
    trimspace(var.api_firebase_service_account_json) != "" ? [{ key = "FIREBASE_SERVICE_ACCOUNT_JSON", value = var.api_firebase_service_account_json, type = "SECRET" }] : [],
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

      run_command = "php artisan queue:work --tries=3 --sleep=3 --timeout=90"

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
