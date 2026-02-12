# -----------------------------------------------------------------------------
# Module: otel-ec2-windows
# Installs OpenTelemetry Collector as a Windows Service on EC2 Windows instances
# Use via user_data (PowerShell) in EC2 launch template
# -----------------------------------------------------------------------------

locals {
  user_data = templatefile("${path.module}/user_data.ps1.tpl", {
    otel_version    = var.otel_version
    config_bucket   = var.config_s3_bucket
    config_key      = var.config_s3_key
    gateway_endpoint = var.gateway_endpoint
  })
}

data "aws_iam_policy_document" "otel_agent" {
  statement {
    sid    = "AllowConfigDownload"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${var.config_s3_bucket}/${var.config_s3_key}"
    ]
  }

  statement {
    sid    = "AllowSSM"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "otel_agent" {
  name_prefix = "otel-agent-ec2-windows-"
  description = "Policy for OTel Collector agent on EC2 Windows"
  policy      = data.aws_iam_policy_document.otel_agent.json
}
