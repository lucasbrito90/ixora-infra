# ── Observability host (Phase 8.8.5) ─────────────────────────────────────────
#
# Provisions infrastructure to run collector/docker-compose.yml on a dedicated
# DigitalOcean Droplet. Docker Compose remains the runtime source of truth.
#
# Secrets are NOT injected via cloud-init. See:
#   scripts/bootstrap-collector-env.sh
#   scripts/deploy-observability.sh
#   docs/specs/observability-foundation/mvp/observability-infrastructure-provisioning.md

locals {
  observability_tags = [
    local.project,
    local.environment,
    "observability",
    "managed-by-opentofu",
  ]

  observability_cloud_init = var.observability_enabled ? templatefile("${path.module}/templates/observability-cloud-init.yaml.tftpl", {
    deploy_path      = var.observability_deploy_path
    grafana_hostname = var.observability_grafana_hostname
    otel_hostname    = var.observability_otel_hostname
  }) : ""

  # Public IP for DNS: Reserved IP when enabled, otherwise Droplet ephemeral IP.
  observability_public_ipv4 = var.observability_enabled ? (
    var.observability_use_reserved_ip
    ? digitalocean_reserved_ip.observability[0].ip_address
    : digitalocean_droplet.observability[0].ipv4_address
  ) : null

  # DNS record names relative to the zone (e.g. "grafana-staging" within "ixora-app.app").
  # trimsuffix removes ".ixora-app.app" from "grafana-staging.ixora-app.app".
  # Falls back to the full hostname when the zone is not configured.
  obs_grafana_record_name = (
    var.observability_dns_zone_name != null && var.observability_grafana_hostname != null
    ? trimsuffix(var.observability_grafana_hostname, ".${var.observability_dns_zone_name}")
    : var.observability_grafana_hostname
  )
  obs_otel_record_name = (
    var.observability_dns_zone_name != null && var.observability_otel_hostname != null
    ? trimsuffix(var.observability_otel_hostname, ".${var.observability_dns_zone_name}")
    : var.observability_otel_hostname
  )

  # Combined guard for DNS record creation: all required inputs must be present.
  obs_dns_records_enabled = (
    var.observability_enabled
    && var.observability_manage_dns
    && var.observability_dns_zone_name != null
    && var.observability_grafana_hostname != null
    && var.observability_otel_hostname != null
  )
}

resource "digitalocean_droplet" "observability" {
  count = var.observability_enabled ? 1 : 0

  name     = local.observability_droplet_name
  region   = local.vpc_region
  size     = var.observability_droplet_size
  image    = var.observability_droplet_image
  vpc_uuid = digitalocean_vpc.staging.id

  ssh_keys          = var.observability_ssh_key_ids
  monitoring        = var.observability_enable_monitoring
  ipv6              = false
  graceful_shutdown = true
  backups           = false
  user_data         = local.observability_cloud_init

  tags = local.observability_tags

  lifecycle {
    # Must be a literal — OpenTofu does not allow variables in prevent_destroy.
    prevent_destroy = true
    ignore_changes = [
      # cloud-init runs once at create time; changing user_data must not replace the Droplet.
      user_data,
    ]
  }
}

# Optional Reserved IP (Floating IP) — disabled by default (Phase 8.8.6).
# Provides DNS stability when the Droplet is replaced. See storage-strategy.md §5.
resource "digitalocean_reserved_ip" "observability" {
  count = var.observability_enabled && var.observability_use_reserved_ip ? 1 : 0

  region = local.vpc_region
}

resource "digitalocean_reserved_ip_assignment" "observability" {
  count = var.observability_enabled && var.observability_use_reserved_ip ? 1 : 0

  ip_address = digitalocean_reserved_ip.observability[0].ip_address
  droplet_id = digitalocean_droplet.observability[0].id
}

resource "digitalocean_volume" "observability" {
  count = var.observability_enabled && var.observability_use_block_volume ? 1 : 0

  name        = "${local.observability_droplet_name}-data"
  region      = local.vpc_region
  size        = var.observability_volume_size_gib
  description = "Ixora observability persistent data (optional Strategy B)"
  tags        = local.observability_tags
}

resource "digitalocean_volume_attachment" "observability" {
  count = var.observability_enabled && var.observability_use_block_volume ? 1 : 0

  droplet_id = digitalocean_droplet.observability[0].id
  volume_id  = digitalocean_volume.observability[0].id
}

resource "digitalocean_firewall" "observability" {
  count = var.observability_enabled ? 1 : 0

  name = local.observability_firewall_name

  droplet_ids = [digitalocean_droplet.observability[0].id]

  # SSH — operator access only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.observability_ssh_allowed_cidrs
  }

  # HTTPS — Caddy (Grafana + OTLP HTTP).
  # TLS certificates are obtained via ACME TLS-ALPN-01 challenge on port 443 (no port 80 required).
  # Direct Collector gRPC/HTTP ports (4317/4318/4319), Grafana (3000), Prometheus (9090),
  # Loki (3100), and Tempo (3200) are never exposed to the public internet — Caddy proxies them.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = var.observability_https_allowed_cidrs
  }

  # ICMP — optional diagnostics from operator networks only
  dynamic "inbound_rule" {
    for_each = length(var.observability_ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      protocol         = "icmp"
      source_addresses = var.observability_ssh_allowed_cidrs
    }
  }

  # Outbound — package installs, image pulls, DNS, TLS, Git, notification APIs (future)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = local.observability_tags
}

# ── Observability DNS records (Phase 8.8.6) ───────────────────────────────────
#
# Created only when ALL of the following are true:
#   - observability_enabled = true
#   - observability_manage_dns = true
#   - observability_dns_zone_name is set (zone must exist in DigitalOcean DNS)
#   - both hostname variables are set
#
# When observability_manage_dns = false, create the A records manually using
# the values in the `observability_dns_requirements` output.
#
# Records point to local.observability_public_ipv4 — Reserved IP when
# observability_use_reserved_ip = true, Droplet ephemeral IP otherwise.

resource "digitalocean_record" "observability_grafana" {
  count = local.obs_dns_records_enabled ? 1 : 0

  domain = var.observability_dns_zone_name
  type   = "A"
  name   = local.obs_grafana_record_name
  value  = local.observability_public_ipv4
  ttl    = var.observability_dns_ttl
}

resource "digitalocean_record" "observability_otel" {
  count = local.obs_dns_records_enabled ? 1 : 0

  domain = var.observability_dns_zone_name
  type   = "A"
  name   = local.obs_otel_record_name
  value  = local.observability_public_ipv4
  ttl    = var.observability_dns_ttl
}
