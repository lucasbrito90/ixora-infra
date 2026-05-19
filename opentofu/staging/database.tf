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

# Allow only the Laravel App Platform app to reach the database cluster (no public ingress rule).
resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "app"
    value = digitalocean_app.api.id
  }

  depends_on = [digitalocean_app.api]
}
