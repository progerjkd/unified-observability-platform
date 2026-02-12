output "user_data" {
  description = "Rendered user_data script for EC2 launch template"
  value       = local.user_data
}

output "iam_policy_arn" {
  description = "IAM policy ARN to attach to the EC2 instance role"
  value       = aws_iam_policy.otel_agent.arn
}
