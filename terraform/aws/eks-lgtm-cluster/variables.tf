variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "obs-lgtm"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS node groups"
  type        = list(string)
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for observability stack"
  type        = string
  default     = "observability"
}

variable "kms_key_arn" {
  description = "KMS key ARN for EBS encryption"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API endpoint (true for demo, false for production)"
  type        = bool
  default     = false
}

variable "eks_node_groups" {
  description = "EKS managed node group definitions. Override in demo.tfvars for minimal sizing."
  type        = any
  default = {
    mimir-ingesters = {
      name            = "mimir-ingesters"
      instance_types  = ["r7g.xlarge"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "ON_DEMAND"
      min_size        = 3
      max_size        = 5
      desired_size    = 3
      labels          = { "observability/role" = "mimir-ingester" }
      taints = [{
        key    = "observability/role"
        value  = "mimir-ingester"
        effect = "NO_SCHEDULE"
      }]
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
            iops        = 3000
            throughput  = 125
          }
        }
      }
    }
    general = {
      name            = "general"
      instance_types  = ["m7g.large"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "ON_DEMAND"
      min_size        = 4
      max_size        = 8
      desired_size    = 6
      labels          = { "observability/role" = "general" }
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 50
            volume_type = "gp3"
          }
        }
      }
    }
    write-path = {
      name            = "write-path"
      instance_types  = ["m7g.large", "m6g.large"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "SPOT"
      min_size        = 3
      max_size        = 6
      desired_size    = 4
      labels          = { "observability/role" = "write-path" }
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
            iops        = 3000
          }
        }
      }
    }
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "observability"
    ManagedBy = "terraform"
  }
}
