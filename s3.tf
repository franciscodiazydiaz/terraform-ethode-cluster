resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${local.name}-artifacts-"
  force_destroy = var.environment == "dev"

  tags = local.tags
}

resource "aws_s3_bucket_acl" "artifacts_private" {
  bucket = aws_s3_bucket.artifacts.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
