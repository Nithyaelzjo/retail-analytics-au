variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to tag/prefix resources"
  type        = string
  default     = "retail-analytics-au"
}

variable "db_username" {
  description = "Master username for the RDS Postgres instance"
  type        = string
  default     = "retail_admin"
}

variable "db_password" {
  description = "Master password for the RDS Postgres instance"
  type        = string
  sensitive   = true
  # Set via terraform.tfvars or TF_VAR_db_password env var — do not hardcode
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
  default     = "retail_analytics"
}

variable "vpc_id" {
  description = "VPC to deploy resources into (use your default VPC id, or create one separately)"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs (at least 2, in different AZs) for RDS and ECS networking"
  type        = list(string)
}

variable "powerbi_client_ip" {
  description = "Your current public IP (no CIDR suffix) — used to scope temporary RDS access for Power BI. Update this whenever your IP changes."
  type        = string
}
