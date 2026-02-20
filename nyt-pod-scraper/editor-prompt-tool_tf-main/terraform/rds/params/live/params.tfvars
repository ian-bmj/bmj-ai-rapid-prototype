accountid   = "721468132385"
platform    = "aws"
product     = "editor-prompt"
project     = "editor-prompt-tool"
stack       = "live"
env         = "live"
scope       = "editor-prompt"
dns_zone_id = "Z01472103KONH2B58TFL5"
costcentre  = "bestpractice"
creator     = "terraform"
region      = "eu-west-1"

vpc_id                  = "vpc-eb42b18c"
rds_subnet_ids          = ["subnet-c37ae78b", "subnet-34fa356e", "subnet-309d1056"]
rds_instance_class      = "db.t3.small"
rds_multi_az            = false
sqs_max_receive_count   = 2
rds_allocated_storage   = 50
rds_domain_prefix       = "editor-prompt"
backup_retention_period = 7

