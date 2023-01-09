resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${local.name}-artifacts-"
  force_destroy = var.environment == "dev"

  tags = local.tags
}
