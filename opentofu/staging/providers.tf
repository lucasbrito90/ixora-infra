terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39"
    }
  }
}

provider "digitalocean" {
  token = var.do_token

  # Spaces API uses separate credentials from the main API token (S3-compatible).
  # Pass via variables / TF_VAR_* at apply time — never commit real values.
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}
