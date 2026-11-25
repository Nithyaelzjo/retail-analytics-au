resource "aws_s3_bucket" "data" {
  bucket = "${var.project_name}-data-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Simple prefix convention: raw/ for API pulls, processed/ for cleaned output
resource "aws_s3_object" "raw_prefix" {
  bucket = aws_s3_bucket.data.id
  key    = "raw/"
}

resource "aws_s3_object" "processed_prefix" {
  bucket = aws_s3_bucket.data.id
  key    = "processed/"
}

data "aws_caller_identity" "current" {}
