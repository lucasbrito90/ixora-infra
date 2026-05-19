resource "digitalocean_spaces_bucket" "assets" {
  count = var.manage_spaces_bucket ? 1 : 0

  name   = var.spaces_bucket_name
  region = var.spaces_region
  acl    = "private"

  lifecycle {
    prevent_destroy = false
  }
}
