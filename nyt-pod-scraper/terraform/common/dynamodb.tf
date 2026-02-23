# =============================================================================
# DynamoDB Tables - Podcasts, Episodes, Distribution Lists
# =============================================================================
# On-demand billing (PAY_PER_REQUEST) avoids capacity planning during early
# stages. All tables use point-in-time recovery for disaster recovery.
# =============================================================================

resource "aws_dynamodb_table" "podcasts" {
  name         = "${var.scope}-${var.stack}-podcasts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  attribute {
    name = "active"
    type = "S"
  }

  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "active-index"
    hash_key        = "active"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Purpose = "Podcast feed metadata"
  }
}

resource "aws_dynamodb_table" "episodes" {
  name         = "${var.scope}-${var.stack}-episodes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "podcast_id"
  range_key    = "episode_id"

  attribute {
    name = "podcast_id"
    type = "S"
  }

  attribute {
    name = "episode_id"
    type = "S"
  }

  attribute {
    name = "published"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "podcast-episodes-index"
    hash_key        = "podcast_id"
    range_key       = "published"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "published"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Purpose = "Episode data and processing status"
  }
}

resource "aws_dynamodb_table" "distribution_lists" {
  name         = "${var.scope}-${var.stack}-distribution-lists"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "list_type"

  attribute {
    name = "list_type"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Purpose = "Email distribution list management"
  }
}
