provider "aws" {
  region = var.region

  default_tags {
    tags = {
      CostCentre  = var.costcentre
      Creator     = var.creator
      Environment = var.stack
      Product     = var.product
      Project     = var.project
      Region      = var.region
      Scope       = var.scope
      Stack       = var.stack
    }
  }
}

provider "aws" {
  alias  = "mgmt"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::385562404581:role/CrossAccountTerraform"
    session_name = "${var.project}-${var.stack}"
  }
}