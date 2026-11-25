resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.subnet_ids

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow Postgres access from the ECS ETL task and Power BI gateway"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from ECS ETL task"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task.id]
  }

  # Temporary: Power BI Desktop connects from your laptop's public IP.
  # This is scoped to a single /32 address, not open to the internet.
  # Update powerbi_client_ip in terraform.tfvars whenever your IP changes.
  ingress {
    description = "Postgres from Power BI Desktop (temporary, IP-scoped)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.powerbi_client_ip}/32"]
  }

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

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type       = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Must be true for Power BI (outside the VPC) to reach this instance at all —
  # access is still restricted to whatever IPs the security group allows above,
  # this just gives the instance a resolvable public endpoint.
  publicly_accessible = true
  skip_final_snapshot = true
  deletion_protection = false

  backup_retention_period = 1

  tags = {
    Project = var.project_name
  }
}
