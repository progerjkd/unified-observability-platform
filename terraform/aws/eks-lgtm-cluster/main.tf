# -----------------------------------------------------------------------------
# EKS cluster for hosting the LGTM observability backend stack
# Uses managed node groups with Graviton (ARM) instances for cost efficiency
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  eks_managed_node_groups = {
    # Mimir ingesters — memory-optimized for TSDB writes
    mimir-ingesters = {
      name            = "mimir-ingesters"
      instance_types  = ["r7g.xlarge"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "ON_DEMAND"
      min_size        = 3
      max_size        = 5
      desired_size    = 3

      labels = {
        "observability/role" = "mimir-ingester"
      }

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
            throughput   = 125
          }
        }
      }
    }

    # General workloads — distributors, queriers, Grafana, gateways
    general = {
      name            = "general"
      instance_types  = ["m7g.large"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "ON_DEMAND"
      min_size        = 4
      max_size        = 8
      desired_size    = 6

      labels = {
        "observability/role" = "general"
      }

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

    # Loki/Tempo write path — can use Spot for cost savings
    write-path = {
      name            = "write-path"
      instance_types  = ["m7g.large", "m6g.large"]
      ami_type        = "AL2023_ARM_64_STANDARD"
      capacity_type   = "SPOT"
      min_size        = 3
      max_size        = 6
      desired_size    = 4

      labels = {
        "observability/role" = "write-path"
      }

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

  tags = var.common_tags
}

# EBS storage class for persistent volumes (Mimir/Loki ingesters)
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    iops      = "3000"
    throughput = "125"
    encrypted = "true"
    kmsKeyId  = var.kms_key_arn
  }

  depends_on = [module.eks]
}

# Namespace for all observability components
resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "purpose"                      = "observability"
    }
  }

  depends_on = [module.eks]
}
