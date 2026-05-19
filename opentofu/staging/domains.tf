# Custom domains — staging-api / staging-admin
#
# App Platform `domain` blocks declare the desired hostname. You must still prove
# ownership via DNS (typically CNAME to the default `*.ondigitalocean.app` hostname
# shown in outputs or in the DigitalOcean control panel).
#
# If `ixora-app.app` uses **DigitalOcean DNS**, you can automate records like:
#
# data "digitalocean_domain" "ixora" {
#   name = "ixora-app.app"
# }
#
# resource "digitalocean_record" "api_staging_cname" {
#   domain = data.digitalocean_domain.ixora.id
#   type   = "CNAME"
#   name   = "staging-api"
#   value  = replace(replace(digitalocean_app.api.live_url, "https://", ""), "/", "")
#   ttl    = 300
# }
#
# Many teams host DNS on Cloudflare or registrars — in that case add the CNAME
# manually using the target hostname from the App Platform UI after first deploy.
