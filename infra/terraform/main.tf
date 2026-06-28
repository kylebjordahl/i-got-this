provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  suffix = var.environment == "production" ? "prod" : "staging"
}

# Durable infra owned by Terraform. Worker CODE + bindings are deployed by
# Wrangler (apps/api); keep binding names in sync with apps/api/wrangler.jsonc.
#
# Phase 0 provisions the D1 database. Queues, KV (sessions), R2, Email Routing
# + the inbound Email Worker, and the KEK secret are added as later phases need
# them (resource schemas should be checked against the pinned provider version
# before `terraform apply`).

resource "cloudflare_d1_database" "primary" {
  account_id = var.cloudflare_account_id
  name       = "${var.name_prefix}-${local.suffix}"
}
