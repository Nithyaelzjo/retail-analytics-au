resource "aws_ecr_repository" "etl" {
  name                 = "${var.project_name}-etl"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

# Keep only the last 10 images to avoid unbounded storage cost
resource "aws_ecr_lifecycle_policy" "etl" {
  repository = aws_ecr_repository.etl.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
