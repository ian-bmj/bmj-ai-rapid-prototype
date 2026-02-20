#----------------------------------------------------
# The bucket for the statefile
# you must replace env with your environment 
# i.e. dev stg live or mgmt
#----------------------------------------------------
bucket = "bmj-live-tfstate"

#----------------------------------------------------
# The key for the project
# you must replace projectname
# example:
# key    = "bmj-terraform-template/infra.tfstate"	
key = "editor-prompt-tool/common/infra.tfstate"

#----------------------------------------------------
#----------------------------------------------------
# The table where the project details are kept
# you must replace env with your environment 
# i.e. dev stg live or mgmt
#----------------------------------------------------
dynamodb_table = "bmj-live-tf"

#----------------------------------------------------
# Region
#----------------------------------------------------
region = "eu-west-1"