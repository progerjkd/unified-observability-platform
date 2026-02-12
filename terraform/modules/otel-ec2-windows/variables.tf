variable "otel_version" {
  description = "OpenTelemetry Collector Contrib version"
  type        = string
  default     = "0.96.0"
}

variable "config_s3_bucket" {
  description = "S3 bucket containing the OTel agent config"
  type        = string
}

variable "config_s3_key" {
  description = "S3 key for the OTel agent config YAML"
  type        = string
  default     = "configs/otel-agent-windows.yaml"
}

variable "gateway_endpoint" {
  description = "OTel gateway endpoint (host:port)"
  type        = string
  default     = "gateway.observability.internal:4317"
}
