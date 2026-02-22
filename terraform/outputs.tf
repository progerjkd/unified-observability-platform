output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "s3_bucket_names" {
  description = "S3 bucket names for LGTM storage"
  value       = module.s3.bucket_names
}

output "irsa_role_arns" {
  description = "IRSA role ARNs for LGTM components"
  value       = module.iam.role_arns
}

output "gateway_endpoint" {
  description = "Internal DNS name for the OTel gateway"
  value       = "gateway.observability.internal:4317"
}

output "gateway_lb_dns" {
  description = "NLB DNS name for the OTel gateway"
  value       = module.networking.otel_gateway_lb_dns
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for demo apps"
  value       = module.ecr.repository_urls
}
