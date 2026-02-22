# ECR repositories for demo sample applications

locals {
  demo_services = ["frontend", "product-api", "inventory"]
}

resource "aws_ecr_repository" "demo" {
  for_each = toset(local.demo_services)

  name                 = "${var.org_prefix}-demo/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = merge(var.common_tags, {
    Component = "demo-app"
    Service   = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "demo" {
  for_each   = aws_ecr_repository.demo
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
