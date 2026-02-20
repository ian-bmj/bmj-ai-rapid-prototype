# Look up the Route 53 zone in the mgmt account
data "aws_route53_zone" "tf_aws_bmjgroup" {
  provider = aws.mgmt
  name     = "tf.aws.bmjgroup.com."
}

# Create a CNAME record pointing your custom name
# at the VPC endpoint that rds Service exposes.
resource "aws_route53_record" "rds_custom_domain_cname" {
  provider = aws.mgmt

  zone_id = data.aws_route53_zone.tf_aws_bmjgroup.zone_id
  name    = local.rds_custom_endpoint # e.g. editor-prompt-rds.dev.tf.aws.bmjgroup.com
  type    = "CNAME"
  ttl     = 300

  records = [
    aws_db_instance.editor_prompt_rds.address # the VPC-only endpoint
  ]
}

# Create the ACM certificate for the custom rds endpoint
resource "aws_acm_certificate" "rds_cert" {
  domain_name       = local.rds_custom_endpoint
  validation_method = "DNS"
}

# Create Route 53 records for DNS validation
resource "aws_route53_record" "acm_validation" {
  provider = aws.mgmt

  for_each = {
    for dvo in aws_acm_certificate.rds_cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.tf_aws_bmjgroup.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.value]
}

# Validate the ACM certificate via DNS
resource "aws_acm_certificate_validation" "rds_cert_validation" {
  certificate_arn         = aws_acm_certificate.rds_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}