variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
  default     = "obs"
}

variable "org_prefix" {
  description = "Organization prefix for globally unique resource names (S3 buckets)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "obs-lgtm"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "onprem_cidrs" {
  description = "On-premises CIDR blocks (via Direct Connect)"
  type        = list(string)
  default     = ["172.16.0.0/12"]
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
