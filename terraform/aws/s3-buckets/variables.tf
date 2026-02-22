variable "org_prefix" {
  description = "Organization prefix for bucket naming"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 server-side encryption"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "observability"
    ManagedBy = "terraform"
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle rules per bucket"
  type = map(object({
    ia_transition_days      = number
    glacier_transition_days = number
    expiration_days         = number
  }))
  default = {
    mimir = {
      ia_transition_days      = 90
      glacier_transition_days = 180
      expiration_days         = 365
    }
    loki = {
      ia_transition_days      = 30
      glacier_transition_days = 90
      expiration_days         = 180
    }
    tempo = {
      ia_transition_days      = 30
      glacier_transition_days = 60
      expiration_days         = 90
    }
  }
}
