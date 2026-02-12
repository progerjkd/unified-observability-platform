variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "launch_type" {
  description = "ECS launch type: FARGATE or EC2"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "launch_type must be FARGATE or EC2"
  }
}

variable "task_cpu" {
  description = "Total task CPU units"
  type        = string
  default     = "1024"
}

variable "task_memory" {
  description = "Total task memory (MiB)"
  type        = string
  default     = "2048"
}

variable "app_image" {
  description = "Docker image for the application container"
  type        = string
}

variable "app_cpu" {
  description = "CPU units for the app container"
  type        = number
  default     = 768
}

variable "app_memory" {
  description = "Memory (MiB) for the app container"
  type        = number
  default     = 1536
}

variable "app_ports" {
  description = "Container ports to expose for the app"
  type        = list(number)
  default     = [8080]
}

variable "app_version" {
  description = "Application version tag for resource attributes"
  type        = string
  default     = "unknown"
}

variable "app_auto_instrumentation_env" {
  description = "Auto-instrumentation environment variables (language-specific)"
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "app_extra_env" {
  description = "Additional environment variables for the app container"
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "otel_collector_image" {
  description = "OTel Collector sidecar image"
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
}

variable "otel_cpu" {
  description = "CPU units for the OTel collector sidecar"
  type        = number
  default     = 256
}

variable "otel_memory" {
  description = "Memory (MiB) for the OTel collector sidecar"
  type        = number
  default     = 512
}

variable "otel_config_content" {
  description = "OTel Collector config YAML content. If empty, uses default."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "additional_containers" {
  description = "Additional container definitions to include in the task"
  type        = list(any)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "observability"
    ManagedBy = "terraform"
  }
}
