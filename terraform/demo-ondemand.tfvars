# On-Demand fallback — use when Spot capacity is unavailable
# Usage: terraform apply -var-file=demo.tfvars -var-file=demo-ondemand.tfvars
#
# This overrides ONLY the capacity_type from demo.tfvars.
# Terraform merges var-files left to right, so this takes precedence.

eks_node_groups = {
  demo = {
    name            = "demo"
    instance_types  = ["t4g.medium"]
    ami_type        = "AL2023_ARM_64_STANDARD"
    capacity_type   = "ON_DEMAND"
    min_size        = 2
    max_size        = 4
    desired_size    = 3
    labels          = { "observability/role" = "general" }
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 30
          volume_type = "gp3"
        }
      }
    }
  }
}
