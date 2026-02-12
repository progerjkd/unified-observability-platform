# -----------------------------------------------------------------------------
# Networking for the observability platform
# VPC, subnets, security groups, and internal DNS for gateway endpoint
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name_prefix}-obs-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  tags = var.common_tags
}

# Security group for OTel gateway — allows inbound OTLP from agents
resource "aws_security_group" "otel_gateway" {
  name_prefix = "${var.name_prefix}-otel-gateway-"
  vpc_id      = module.vpc.vpc_id
  description = "Allow OTLP traffic from OTel agents to gateway"

  ingress {
    description = "OTLP gRPC from VPC"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "OTLP HTTP from VPC"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "OTLP gRPC from on-prem via Direct Connect"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = var.onprem_cidrs
  }

  ingress {
    description = "OTLP HTTP from on-prem via Direct Connect"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = var.onprem_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-otel-gateway"
  })
}

# Private hosted zone for internal DNS resolution
resource "aws_route53_zone" "observability_internal" {
  name = "observability.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = var.common_tags
}

# Internal NLB for the OTel gateway
resource "aws_lb" "otel_gateway" {
  name               = "${var.name_prefix}-otel-gw"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.otel_gateway.id]

  enable_cross_zone_load_balancing = true

  tags = var.common_tags
}

resource "aws_lb_target_group" "otel_grpc" {
  name        = "${var.name_prefix}-otel-grpc"
  port        = 4317
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = 13133
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "otel_grpc" {
  load_balancer_arn = aws_lb.otel_gateway.arn
  port              = 4317
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otel_grpc.arn
  }
}

# DNS record pointing to the gateway NLB
resource "aws_route53_record" "gateway" {
  zone_id = aws_route53_zone.observability_internal.zone_id
  name    = "gateway.observability.internal"
  type    = "A"

  alias {
    name                   = aws_lb.otel_gateway.dns_name
    zone_id                = aws_lb.otel_gateway.zone_id
    evaluate_target_health = true
  }
}
