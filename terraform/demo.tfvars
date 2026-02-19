# Demo / interview environment — minimal sizing
# Estimated cost: ~$100-150/month (vs ~$1,500+ for production)
#
# Usage:
#   cd terraform && terraform plan -var-file=demo.tfvars -out=tfplan
#   cd terraform && terraform apply tfplan

aws_region      = "us-east-1"
environment     = "demo"
org_prefix      = "odontoagil"
cluster_name    = "obs-lgtm-demo"
cluster_version = "1.35"  # Latest version - avoids extended support fees
vpc_cidr                       = "10.0.0.0/16"
onprem_cidrs                   = ["172.16.0.0/12"]
cluster_endpoint_public_access = true  # Allow kubectl/Terraform from laptop

# Single small node group — Spot with diversified pool, autoscaler manages scaling
eks_node_groups = {
  demo = {
    name            = "demo"
    instance_types  = ["t4g.medium", "t4g.large", "m6g.medium", "m7g.medium"]
    ami_type        = "AL2023_ARM_64_STANDARD"
    capacity_type   = "SPOT"
    min_size        = 2
    max_size        = 10
    desired_size    = 2
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
