# -----------------------------------------------------------------------------
# Module: otel-ecs-sidecar
# Creates an ECS task definition with an OTel Collector sidecar container
# Supports both Fargate and EC2 launch types
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app_with_otel" {
  family                   = var.service_name
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode(concat(
    [
      {
        name      = "app"
        image     = var.app_image
        essential = true
        cpu       = var.app_cpu
        memory    = var.app_memory

        portMappings = [
          for port in var.app_ports : {
            containerPort = port
            hostPort      = var.launch_type == "FARGATE" ? port : 0
            protocol      = "tcp"
          }
        ]

        environment = concat(
          [
            { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4318" },
            { name = "OTEL_SERVICE_NAME", value = var.service_name },
            { name = "OTEL_RESOURCE_ATTRIBUTES", value = "deployment.environment=${var.environment},service.version=${var.app_version}" },
          ],
          var.app_auto_instrumentation_env,
          var.app_extra_env
        )

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = "/ecs/${var.service_name}"
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "app"
          }
        }

        dependsOn = [{
          containerName = "otel-collector"
          condition     = "START"
        }]
      },
      {
        name      = "otel-collector"
        image     = var.otel_collector_image
        essential = false
        cpu       = var.otel_cpu
        memory    = var.otel_memory

        command = ["--config", "/etc/otel/config.yaml"]

        environment = [
          {
            name  = "AOT_CONFIG_CONTENT"
            value = var.otel_config_content != "" ? var.otel_config_content : file("${path.module}/default-fargate-config.yaml")
          }
        ]

        portMappings = [
          { containerPort = 4317, hostPort = 4317, protocol = "tcp" },
          { containerPort = 4318, hostPort = 4318, protocol = "tcp" },
          { containerPort = 13133, hostPort = 13133, protocol = "tcp" }
        ]

        healthCheck = {
          command     = ["CMD-SHELL", "curl -f http://localhost:13133/health || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 15
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = "/ecs/${var.service_name}"
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "otel"
          }
        }
      }
    ],
    var.additional_containers
  ))

  tags = merge(var.common_tags, {
    Service = var.service_name
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}
