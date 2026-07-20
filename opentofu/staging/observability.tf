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

  # HTTPS — Caddy (Grafana + OTLP HTTP). Collector gRPC/HTTP direct ports stay off the public internet.
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
