terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "region_name" {
  type        = string
  description = "The region short name (e.g., use1, use2) used for naming resources"
}

variable "is_primary" {
  type        = bool
  description = "Whether this module instance is the primary region (creates Aurora Global Cluster)"
  default     = false
}

# ─────────────────────────────────────────────
# Sensitive runtime credentials (Open WebUI)
# ─────────────────────────────────────────────

variable "webui_secret_key" {
  type        = string
  sensitive   = true
  description = "Secret key for Open WebUI session signing (WEBUI_SECRET_KEY)"
}

variable "global_cluster_id" {
  type    = string
  default = null
}

variable "enable_guardduty" {
  type        = bool
  default     = false
  description = "Enable GuardDuty detector (requires subscription in AWS account)"
}

variable "aurora_engine_version" {
  type    = string
  default = "15.10" # must be in the list from the command above
}
