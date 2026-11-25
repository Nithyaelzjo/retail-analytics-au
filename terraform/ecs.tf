resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-task-sg"
  description = "ETL Fargate task - outbound only (calls ABS/RBA APIs, writes to S3/RDS)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "etl" {
  name              = "/ecs/${var.project_name}-etl"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "etl" {
  family                   = "${var.project_name}-etl"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                       = "512"   # 0.5 vCPU — enough for a pandas ETL job
  memory                    = "1024"  # 1 GB
  execution_role_arn        = aws_iam_role.ecs_execution.arn
  task_role_arn             = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "etl"
    image     = "${aws_ecr_repository.etl.repository_url}:latest"
    essential = true
    environment = [
      { name = "S3_BUCKET", value = aws_s3_bucket.data.bucket },
      { name = "DB_HOST", value = aws_db_instance.this.address },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username }
      # DB_PASSWORD is intentionally NOT set here — pull it from Secrets
      # Manager or SSM Parameter Store at runtime instead of plaintext env vars.
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.etl.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "etl"
      }
    }
  }])

  tags = {
    Project = var.project_name
  }
}
