variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with D1/Queues/Workers/Email permissions."
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID."
}

variable "environment" {
  type        = string
  description = "Deployment environment (staging | production)."
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "name_prefix" {
  type        = string
  default     = "igt"
  description = "Resource name prefix."
}
