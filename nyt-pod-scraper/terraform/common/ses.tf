# =============================================================================
# SES - Email Delivery
# =============================================================================
# The sender email identity must be verified before emails can be sent.
# New SES accounts start in sandbox mode (verified recipients only).
# =============================================================================

resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}
