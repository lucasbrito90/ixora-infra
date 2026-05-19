locals {
  project     = "ixora"
  environment = "staging"
  vpc_region  = "tor1"
  app_region  = "tor" # App Platform Toronto slug (differs from Spaces/DB tor1)

  api_app_name   = "ixora-api-staging"
  admin_app_name = "ixora-admin-staging"

  # CDN-style public URL pattern for Spaces (public reads still require ACL/CORS policy as needed).
  spaces_cdn_host = "${var.spaces_bucket_name}.${var.spaces_region}.cdn.digitaloceanspaces.com"
}
