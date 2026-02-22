output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for k, v in aws_ecr_repository.demo : k => v.repository_url }
}

output "registry_id" {
  description = "The registry ID (AWS account ID)"
  value       = values(aws_ecr_repository.demo)[0].registry_id
}
