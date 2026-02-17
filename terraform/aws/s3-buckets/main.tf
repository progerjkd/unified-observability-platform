locals {
  buckets = ["obs-mimir", "obs-loki", "obs-tempo"]
}

resource "aws_s3_bucket" "observability" {
  for_each = toset(local.buckets)
  bucket   = "${var.org_prefix}-${each.key}"

  tags = merge(var.common_tags, {
    Component = each.key
  })
}

resource "aws_s3_bucket_versioning" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"
    filter {}

    transition {
      days          = var.lifecycle_rules[each.key].ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_rules[each.key].glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.lifecycle_rules[each.key].expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
