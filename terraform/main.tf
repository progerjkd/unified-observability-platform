# -----------------------------------------------------------------------------
# Root Terraform configuration — Unified Observability Platform
# Orchestrates all AWS modules for the complete infrastructure
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  # Remote state (configure for your environment)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "observability/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Configure kubernetes provider after EKS is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ------- KMS Key for encryption -------

resource "aws_kms_key" "observability" {
  description             = "KMS key for observability platform encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "observability" {
  name          = "alias/observability"
  target_key_id = aws_kms_key.observability.key_id
}

# ------- Networking -------

module "networking" {
  source = "./aws/networking"

  name_prefix  = var.name_prefix
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  onprem_cidrs = var.onprem_cidrs
  common_tags  = local.common_tags
}

# ------- EKS Cluster -------

module "eks" {
  source = "./aws/eks-lgtm-cluster"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  vpc_id                         = module.networking.vpc_id
  private_subnet_ids             = module.networking.private_subnet_ids
  kms_key_arn                    = aws_kms_key.observability.arn
  eks_node_groups                = var.eks_node_groups
  common_tags                    = local.common_tags
}

# ------- S3 Buckets -------

module "s3" {
  source = "./aws/s3-buckets"

  org_prefix  = var.org_prefix
  kms_key_arn = aws_kms_key.observability.arn
  common_tags = local.common_tags
}

# ------- ECR Repositories (demo apps) -------

module "ecr" {
  source = "./aws/ecr"

  org_prefix  = var.org_prefix
  common_tags = local.common_tags
}

# ------- IAM / IRSA Roles -------

module "iam" {
  source = "./aws/iam-roles"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  bucket_arns       = module.s3.bucket_arns
  kms_key_arn       = aws_kms_key.observability.arn
  common_tags       = local.common_tags
}

# ------- Locals -------

locals {
  common_tags = {
    Project     = "observability"
    ManagedBy   = "terraform"
    Environment = var.environment
    CostCenter  = "observability-${var.environment}"
    Owner       = var.org_prefix
  }
}
