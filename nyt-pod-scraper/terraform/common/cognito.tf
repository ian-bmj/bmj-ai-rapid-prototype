# =============================================================================
# Cognito - Admin Authentication
# =============================================================================
# Cognito User Pool for the admin SPA. Admin-invited users only.
# =============================================================================

resource "aws_cognito_user_pool" "admin" {
  name = "${var.scope}-${var.stack}-admin-pool"

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your Pod Monitor Admin Account"
      email_message = "Your username is {username} and temporary password is {####}. Please log in at the Pod Monitor admin portal to set your permanent password."
      sms_message   = "Your Pod Monitor username is {username} and temporary password is {####}."
    }
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    Purpose = "Admin authentication"
  }
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.scope}-${var.stack}-spa-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers  = ["COGNITO"]
}

resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Administrators with full access to Pod Monitor management"
}

resource "aws_cognito_user_group" "viewer" {
  name         = "viewer"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Viewers with read-only access to podcast data and reports"
}
