#----------------------------------------------------
# S3 backend for Terraform state (live)
#----------------------------------------------------
bucket = "bmj-live-tfstate"

key = "pod-monitor/common/infra.tfstate"

dynamodb_table = "bmj-live-tf"

region = "eu-west-2"
