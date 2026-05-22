resource "digitalocean_database_cluster" "postgres" {
  name       = var.db_cluster_name
  engine     = "pg"
  version    = var.db_pg_version
  size       = var.db_node_size
  region     = local.vpc_region
  node_count = var.db_node_count

  private_network_uuid = digitalocean_vpc.staging.id

  tags = ["ixora", "staging", "managed-by-opentofu"]

  # Staging / non-prod lifecycle hints (provider-dependent; tags document intent).
  lifecycle {
    prevent_destroy = false
  }
}

resource "digitalocean_database_db" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "ixora_staging"
}

resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "ixora_app"
}

# Trusted sources: allow the entire staging VPC CIDR on the private network.
#
# `type = "app"` + App Platform app ID does not reliably cover worker egress; workers can use
# different outbound paths than the web service. Using the VPC ip_range matches DigitalOcean's
# documented approach for DBaaS + VPC (one CIDR rule, private hostname only — still no public DB).
resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "ip_addr"
    value = digitalocean_vpc.staging.ip_range
  }

  depends_on = [
    digitalocean_database_cluster.postgres,
    digitalocean_vpc.staging,
  ]
}
