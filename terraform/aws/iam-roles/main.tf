# -----------------------------------------------------------------------------
# IRSA roles for LGTM stack components to access their respective S3 buckets
# -----------------------------------------------------------------------------

locals {
  components = {
    mimir = {
      namespace       = var.k8s_namespace
      service_account = "mimir"
      bucket_key      = "obs-mimir"
    }
    loki = {
      namespace       = var.k8s_namespace
      service_account = "loki"
      bucket_key      = "obs-loki"
    }
    tempo = {
      namespace       = var.k8s_namespace
      service_account = "tempo"
      bucket_key      = "obs-tempo"
    }
  }
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  for_each = local.components

  role_name = "${var.cluster_name}-${each.key}-s3-access"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${each.value.namespace}:${each.value.service_account}"]
    }
  }

  tags = var.common_tags
}

resource "aws_iam_role_policy" "s3_access" {
  for_each = local.components

  name = "${each.key}-s3-access"
  role = module.irsa[each.key].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.bucket_arns[each.value.bucket_key],
          "${var.bucket_arns[each.value.bucket_key]}/*"
        ]
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}
