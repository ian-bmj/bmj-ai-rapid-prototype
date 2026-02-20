################################################################################
## START CERTIFICATE ##
################################################################################

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.1.1"

  domain_name = format("*.%s.%s.%s", var.namespace, var.stack, var.domain_name_suffix) # Primary Wildcard domain

  zone_id = var.dns_zone_id

  # uncomment and update if you want SAN records to be created!

  # Valid SANs
  # subject_alternative_names = [
  #   format("alerts.%s.%s.%s", var.namespace, var.stack, var.domain_name_suffix),
  #   format("api.%s.%s.%s", var.namespace, var.stack, var.domain_name_suffix),
  # ]

  validation_method   = "DNS"
  wait_for_validation = true

}

################################################################################
## END CERTIFICATE ##
################################################################################

resource "aws_ssm_parameter" "learning_certificate_arn" {
  name  = "${var.namespace}-${var.stack}-certificate"
  type  = "String"
  value = module.acm.acm_certificate_arn
}