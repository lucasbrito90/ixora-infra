output "vpc_id" {
  description = "Staging VPC UUID."
  value       = digitalocean_vpc.staging.id
}

output "vpc_name" {
  description = "Staging VPC name."
  value       = digitalocean_vpc.staging.name
}

output "database_cluster_id" {
  description = "Managed Postgres cluster ID."
  value       = digitalocean_database_cluster.postgres.id
}

output "database_host_private" {
  description = "PostgreSQL hostname reachable from resources in the VPC (e.g. App Platform attached to this VPC)."
  value       = digitalocean_database_cluster.postgres.private_host
}

output "database_port" {
  description = "PostgreSQL port."
  value       = digitalocean_database_cluster.postgres.port
}

output "database_user" {
  description = "Application database user (ixora_app)."
  value       = digitalocean_database_user.app.name
}

output "database_name" {
  description = "Laravel DB name wired to App Platform (defaultdb)."
  value       = "defaultdb"
}

output "database_password" {
  description = "Application database user password (rotate via DO UI/API if leaked)."
  value       = digitalocean_database_user.app.password
  sensitive   = true
}

output "spaces_bucket_name" {
  description = "Spaces bucket name when managed by this stack."
  value       = var.manage_spaces_bucket ? digitalocean_spaces_bucket.assets[0].name : null
}

output "spaces_origin_endpoint" {
  description = "S3-compatible origin URL pattern for the bucket (private ACL)."
  value       = var.manage_spaces_bucket ? "https://${var.spaces_bucket_name}.${var.spaces_region}.digitaloceanspaces.com" : null
}

output "spaces_cdn_url_example" {
  description = "Typical public CDN base URL for Objects CDN (enable/configure in DO console if needed)."
  value       = "https://${local.spaces_cdn_host}"
}

output "api_app_id" {
  description = "App Platform ID for the Laravel API."
  value       = digitalocean_app.api.id
}

output "api_live_url" {
  description = "Default App Platform URL for the API (custom domain routes here before DNS is complete)."
  value       = digitalocean_app.api.live_url
}

output "admin_app_id" {
  description = "App Platform ID for Nuxt static admin."
  value       = digitalocean_app.admin.id
}

output "admin_live_url" {
  description = "Default App Platform URL for the admin static site."
  value       = digitalocean_app.admin.live_url
}

# ── Observability host (Phase 8.8.5) ─────────────────────────────────────────

output "observability_enabled" {
  description = "Whether the observability Droplet stack is provisioned by this module."
  value       = var.observability_enabled
}

output "observability_droplet_id" {
  description = "DigitalOcean Droplet ID for the observability host."
  value       = var.observability_enabled ? digitalocean_droplet.observability[0].id : null
}

output "observability_public_ipv4" {
  description = "Public IPv4 address of the observability Droplet. Point grafana-staging and otel-staging DNS A records here."
  value       = var.observability_enabled ? digitalocean_droplet.observability[0].ipv4_address : null
}

output "observability_private_ipv4" {
  description = "Private VPC IPv4 address of the observability Droplet (App Platform VPC peers may reach this for future private OTLP)."
  value       = var.observability_enabled ? digitalocean_droplet.observability[0].ipv4_address_private : null
}

output "observability_grafana_url" {
  description = "Public Grafana URL (HTTPS via Caddy). Requires DNS + collector/.env + deploy script after apply."
  value       = var.observability_enabled ? "https://${var.observability_grafana_hostname}" : null
}

output "observability_otlp_http_url" {
  description = "Public OTLP HTTP endpoint for App Platform and mobile (HTTPS via Caddy → Collector :4318)."
  value       = var.observability_enabled ? "https://${var.observability_otel_hostname}" : null
}

output "observability_ssh_command" {
  description = "Example SSH command for operators (replace user if not root)."
  value       = var.observability_enabled ? "ssh root@${digitalocean_droplet.observability[0].ipv4_address}" : null
}

output "observability_deploy_path" {
  description = "Path on the host where ixora-infra must be deployed."
  value       = var.observability_deploy_path
}

output "observability_firewall_id" {
  description = "DigitalOcean Cloud Firewall ID for the observability Droplet."
  value       = var.observability_enabled ? digitalocean_firewall.observability[0].id : null
}
