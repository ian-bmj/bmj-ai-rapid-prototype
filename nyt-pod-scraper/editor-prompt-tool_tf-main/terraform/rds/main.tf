#####################################################
##  Fetch Credentials
#####################################################
data "aws_secretsmanager_secret_version" "rds_postgres_cluster_creds" {
  secret_id = "rds_postgres_cluster_creds/${var.product}/${var.stack}/cluster-creds"
}

locals {
  rds_cluster_credentials = jsondecode(data.aws_secretsmanager_secret_version.rds_postgres_cluster_creds.secret_string)
}

locals {
  rds_custom_endpoint = "rds.${var.rds_domain_prefix}.${var.stack}.tf.aws.bmjgroup.com"
}


resource "random_id" "db" {
  byte_length = 8
}

#####################################################
##  Create RDS Database
#####################################################


resource "aws_db_instance" "editor_prompt_rds" {
  identifier                      = "${var.product}-${var.stack}-postgres-db"
  allocated_storage               = var.rds_allocated_storage
  storage_type                    = "gp3"
  engine                          = "postgres"
  engine_version                  = var.db_engine_version
  instance_class                  = var.rds_instance_class
  db_name                         = local.rds_cluster_credentials["database"]
  username                        = local.rds_cluster_credentials["username"]
  password                        = local.rds_cluster_credentials["password"]
  db_subnet_group_name            = aws_db_subnet_group.editor_prompt_rds.id
  parameter_group_name            = "default.postgres15"
  skip_final_snapshot             = true
  auto_minor_version_upgrade      = true
  vpc_security_group_ids          = ["${aws_security_group.rds_sg.id}"]
  multi_az                        = var.rds_multi_az
  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_period # Automatic backup retention set to 7 days
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn

  # Add the RDS tags from local (i,e CycleState + Default Tags from provider)
  tags = local.cyclestate_tag
}


resource "aws_db_subnet_group" "editor_prompt_rds" {
  name       = "${var.product}-${var.stack}-subnet-group"
  subnet_ids = var.rds_subnet_ids
}

resource "aws_iam_role" "rds_monitoring_role" {
  name = "${var.product}-${var.stack}-postgres-db-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_attach" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}