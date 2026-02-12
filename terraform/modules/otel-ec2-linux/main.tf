# -----------------------------------------------------------------------------
# Module: otel-ec2-linux
# Installs OpenTelemetry Collector as a systemd service on EC2 Linux instances
# Use via user_data or as a standalone module with SSM Run Command
# -----------------------------------------------------------------------------

locals {
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
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
  name_prefix = "otel-agent-ec2-linux-"
  description = "Policy for OTel Collector agent on EC2 Linux"
  policy      = data.aws_iam_policy_document.otel_agent.json
}
