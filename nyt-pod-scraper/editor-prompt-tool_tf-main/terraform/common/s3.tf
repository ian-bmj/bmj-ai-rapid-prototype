##############S3 Bucket#########################
resource "aws_s3_bucket" "editor_prompt_tool_bucket" {
  bucket = "${var.scope}-tool-${var.stack}"
}

# Enable versioning
resource "aws_s3_bucket_versioning" "editor_prompt_tool_bucket_versioning" {
  bucket = aws_s3_bucket.editor_prompt_tool_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "editor_prompt_tool_bucket_encryption" {
  bucket = aws_s3_bucket.editor_prompt_tool_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "editor_prompt_tool_bucket_s3_bucket" {
  bucket = aws_s3_bucket.editor_prompt_tool_bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
