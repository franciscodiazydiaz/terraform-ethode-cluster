resource "aws_s3_object" "artifacts" {
  for_each = fileset("./artifacts/", "*.tar.gz")

  bucket                 = aws_s3_bucket.artifacts.id
  key                    = each.value
  source                 = "./artifacts/${each.value}"
  server_side_encryption = "AES256"

  # Triggers an update only if the file changes
  source_hash = filebase64sha256("./artifacts/${each.value}")
}
