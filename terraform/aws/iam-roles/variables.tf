variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for EKS IRSA"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for observability stack"
  type        = string
  default     = "observability"
}

variable "bucket_arns" {
  description = "Map of bucket key to ARN from s3-buckets module"
  type        = map(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN used for S3 encryption"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "observability"
    ManagedBy = "terraform"
  }
}
