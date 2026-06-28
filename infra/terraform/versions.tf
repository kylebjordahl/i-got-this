terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # State lives in an R2 bucket via the S3-compatible backend. Fill in the
  # account-specific endpoint and create the bucket out-of-band first, then:
  #   terraform init -backend-config=backend.<env>.hcl
  #
  # backend "s3" {
  #   bucket                      = "igt-tfstate"
  #   key                         = "envs/staging/terraform.tfstate"
  #   region                      = "auto"
  #   endpoints                   = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  # }
}
