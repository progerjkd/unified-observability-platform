output "role_arns" {
  description = "Map of component name to IAM role ARN for IRSA"
  value       = { for k, v in module.irsa : k => v.iam_role_arn }
}
