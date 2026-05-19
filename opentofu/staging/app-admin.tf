resource "digitalocean_app" "admin" {
  spec {
    name   = local.admin_app_name
    region = local.app_region

    domain {
      name = var.admin_domain
      type = "PRIMARY"
    }

    static_site {
      name          = "admin"
      build_command = "npm ci && npm run generate"
      output_dir    = ".output/public"

      github {
        repo           = var.github_repo_admin
        branch         = var.github_branch
        deploy_on_push = true
      }

      dynamic "env" {
        for_each = {
          for k, v in {
            NUXT_PUBLIC_API_BASE_URL                  = var.nuxt_public_api_base_url
            NUXT_PUBLIC_FIREBASE_API_KEY              = var.nuxt_public_firebase_api_key
            NUXT_PUBLIC_FIREBASE_AUTH_DOMAIN          = var.nuxt_public_firebase_auth_domain
            NUXT_PUBLIC_FIREBASE_PROJECT_ID           = var.nuxt_public_firebase_project_id
            NUXT_PUBLIC_FIREBASE_STORAGE_BUCKET       = var.nuxt_public_firebase_storage_bucket
            NUXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID  = var.nuxt_public_firebase_messaging_sender_id
            NUXT_PUBLIC_FIREBASE_APP_ID               = var.nuxt_public_firebase_app_id
          } : k => v if trimspace(v) != ""
        }
        content {
          key   = env.key
          value = env.value
          type  = "GENERAL"
          scope = "BUILD_TIME"
        }
      }
    }

    ingress {
      rule {
        component {
          name = "admin"
        }
        match {
          path {
            prefix = "/"
          }
        }
      }
    }
  }
}
