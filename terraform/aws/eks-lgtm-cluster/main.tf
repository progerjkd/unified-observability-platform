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

  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  # Core addons — EBS CSI driver managed separately to avoid circular IRSA dependency
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  # Node groups are passed in via variable — see var.eks_node_groups
  # Demo mode: override with demo.tfvars (2x t4g.medium Spot, ~$50/mo)
  # Prod mode: default (13 nodes across 3 groups, ~$1,500/mo)
  eks_managed_node_groups = var.eks_node_groups

  tags = var.common_tags
}

# ------- EBS CSI Driver (managed outside EKS module to avoid circular dep) -------

# IRSA role — needs OIDC provider from EKS, so must be created after cluster
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Addon — depends on both the cluster and the IRSA role
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn

  depends_on = [module.eks]
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
    type                        = "gp3"
    iops                        = "3000"
    throughput                  = "125"
    encrypted                   = "true"
    kmsKeyId                    = var.kms_key_arn
    "tagSpecification_1"        = "Name={{ .PVCNamespace }}/{{ .PVCName }}"
    "tagSpecification_2"        = "Project=${lookup(var.common_tags, "Project", "observability")}"
    "tagSpecification_3"        = "Environment=${lookup(var.common_tags, "Environment", "prod")}"
    "tagSpecification_4"        = "ManagedBy=kubernetes"
    "tagSpecification_5"        = "CostCenter=${lookup(var.common_tags, "CostCenter", "observability")}"
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
