# Legacy Terraform (Serverless Architecture)

These files are from the original serverless prototype architecture using
Lambda, Step Functions, API Gateway, and CloudFront.

The project has been restructured to use **EKS** following BMJ patterns from
`editor-prompt-tool_tf-main` and `editor-prompt-tool_eks-main`.

The active Terraform code is in:
- `terraform/eks/` -- VPC, EKS cluster, ECR
- `terraform/common/` -- S3, DynamoDB, IAM/IRSA, Cognito, SES

These legacy files are kept for reference only and should not be used.
