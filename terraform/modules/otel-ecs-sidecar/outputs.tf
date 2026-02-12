output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app_with_otel.arn
}

output "task_definition_family" {
  description = "Family of the ECS task definition"
  value       = aws_ecs_task_definition.app_with_otel.family
}

output "task_definition_revision" {
  description = "Latest revision of the ECS task definition"
  value       = aws_ecs_task_definition.app_with_otel.revision
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}
