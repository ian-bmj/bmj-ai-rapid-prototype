resource "aws_security_group" "rds_sg" {
  name        = "${var.product}-rds-${var.stack}-sg"
  description = "Security group for Editor Prompt RDS ${var.stack} cluster"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow RDS access from internal CIDR"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/12"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
