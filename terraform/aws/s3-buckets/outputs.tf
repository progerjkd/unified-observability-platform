output "bucket_arns" {
  description = "Map of bucket name to ARN"
  value       = { for k, v in aws_s3_bucket.observability : k => v.arn }
}

output "bucket_ids" {
  description = "Map of bucket name to ID"
  value       = { for k, v in aws_s3_bucket.observability : k => v.id }
}

output "bucket_names" {
  description = "Map of bucket key to full bucket name"
  value       = { for k, v in aws_s3_bucket.observability : k => v.bucket }
}
