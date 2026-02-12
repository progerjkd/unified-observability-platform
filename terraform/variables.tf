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
