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
      Namespace   = var.namespace
    }
  }
}