variable "org_prefix" {
  description = "Organization prefix for repository naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
