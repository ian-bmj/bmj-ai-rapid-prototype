# Superseded

This Terraform configuration has been superseded by the BMJ-pattern-compliant
code in the top-level `terraform/` directory:

- `terraform/eks/` -- VPC, EKS cluster, ECR
- `terraform/common/` -- S3, DynamoDB, IAM/IRSA, Cognito, SES

See `DEPLOY.md` in the project root for deployment instructions.
