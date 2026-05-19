resource "digitalocean_vpc" "staging" {
  name   = "ixora-staging-vpc-tor1"
  region = local.vpc_region

  tags = ["ixora", "staging", "managed-by-opentofu"]
}
