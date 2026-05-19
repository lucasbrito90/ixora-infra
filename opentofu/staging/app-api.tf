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

      # ── Core Laravel (non-secret) ─────────────────────────────────────────
      env {
        key   = "APP_NAME"
        value = "Ixora"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "APP_ENV"
        value = "staging"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "APP_DEBUG"
        value = "false"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "APP_URL"
        value = "https://${var.api_domain}"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "LOG_CHANNEL"
        value = "stderr"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "QUEUE_CONNECTION"
        value = "database"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }

      # ── PostgreSQL (managed cluster, VPC-private) ─────────────────────────
      env {
        key   = "DB_CONNECTION"
        value = "pgsql"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DB_HOST"
        value = digitalocean_database_cluster.postgres.private_host
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DB_PORT"
        value = tostring(digitalocean_database_cluster.postgres.port)
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DB_DATABASE"
        value = digitalocean_database_cluster.postgres.database
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DB_USERNAME"
        value = digitalocean_database_cluster.postgres.user
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DB_PASSWORD"
        value = digitalocean_database_cluster.postgres.password
        type  = "SECRET"
        scope = "RUN_TIME"
      }

      # ── DigitalOcean Spaces (runtime credentials + endpoints) ────────────
      env {
        key   = "DO_SPACES_BUCKET"
        value = var.spaces_bucket_name
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DO_SPACES_REGION"
        value = var.spaces_region
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DO_SPACES_ENDPOINT"
        value = "https://${var.spaces_region}.digitaloceanspaces.com"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
      env {
        key   = "DO_SPACES_CDN_URL"
        value = "https://${local.spaces_cdn_host}"
        type  = "GENERAL"
        scope = "RUN_TIME"
      }

      dynamic "env" {
        for_each = var.api_do_spaces_key != "" ? { DO_SPACES_KEY = var.api_do_spaces_key } : {}
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.api_do_spaces_secret != "" ? { DO_SPACES_SECRET = var.api_do_spaces_secret } : {}
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
          scope = "RUN_TIME"
        }
      }

      # ── Optional secrets supplied via variables / TF_VAR ──────────────────
      dynamic "env" {
        for_each = var.api_app_key != "" ? { APP_KEY = var.api_app_key } : {}
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.api_firebase_service_account_json != "" ? { FIREBASE_SERVICE_ACCOUNT_JSON = var.api_firebase_service_account_json } : {}
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.api_mail_password != "" ? { MAIL_PASSWORD = var.api_mail_password } : {}
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.admin_access_review_email != "" ? { ADMIN_ACCESS_REVIEW_EMAIL = var.admin_access_review_email } : {}
        content {
          key   = env.key
          value = env.value
          type  = "GENERAL"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.api_env_general
        content {
          key   = env.key
          value = env.value
          type  = "GENERAL"
          scope = "RUN_TIME"
        }
      }

      dynamic "env" {
        for_each = var.api_secrets_extra
        content {
          key   = env.key
          value = env.value
          type  = "SECRET"
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
    digitalocean_vpc.staging,
  ]
}
