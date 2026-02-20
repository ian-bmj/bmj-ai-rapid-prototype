output "rds_endpoint" {
  value       = aws_db_instance.editor_prompt_rds.endpoint
  description = "RDS PostgreSQL endpoint"
}

output "rds_identifier" {
  value       = aws_db_instance.editor_prompt_rds.id
  description = "RDS instance identifier"
}