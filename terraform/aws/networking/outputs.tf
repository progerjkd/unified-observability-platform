output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "otel_gateway_sg_id" {
  description = "Security group ID for OTel gateway"
  value       = aws_security_group.otel_gateway.id
}

output "otel_gateway_lb_dns" {
  description = "DNS name of the OTel gateway NLB"
  value       = aws_lb.otel_gateway.dns_name
}

output "otel_gateway_target_group_arn" {
  description = "Target group ARN for OTel gateway gRPC"
  value       = aws_lb_target_group.otel_grpc.arn
}

output "internal_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.observability_internal.zone_id
}
