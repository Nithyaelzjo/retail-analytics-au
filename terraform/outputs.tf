output "s3_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.etl.repository_url
}

output "rds_endpoint" {
  value     = aws_db_instance.this.address
  sensitive = true
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}
