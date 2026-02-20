# BMJ Pod Monitor - EKS Deployment Guide

Complete step-by-step guide for deploying the Pod Monitor podcast intelligence platform
on AWS using EKS (Elastic Kubernetes Service), Terraform, and supporting AWS services.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Cloud (eu-west-2)                     │
│                                                                  │
│  ┌──────────┐     ┌──────────────────────────────────────────┐  │
│  │   ALB    │────▶│         EKS Cluster                      │  │
│  │(Internet)│     │  ┌─────────────────────────────────────┐ │  │
│  └──────────┘     │  │  pod-monitor namespace               │ │  │
│                   │  │                                      │ │  │
│                   │  │  ┌──────────┐  ┌──────────────────┐ │ │  │
│                   │  │  │ API Pod  │  │ API Pod (replica) │ │ │  │
│                   │  │  │ Flask +  │  │ Flask +           │ │ │  │
│                   │  │  │ Admin UI │  │ Admin UI          │ │ │  │
│                   │  │  └────┬─────┘  └────────┬─────────┘ │ │  │
│                   │  │       │     IRSA          │          │ │  │
│                   │  │  ┌────┴──────────────────┴────────┐ │ │  │
│                   │  │  │   CronJobs:                     │ │ │  │
│                   │  │  │   - scraper (every 6h)          │ │ │  │
│                   │  │  │   - daily digest (8am UTC)      │ │ │  │
│                   │  │  │   - weekly digest (Mon 8am)     │ │ │  │
│                   │  │  └────────────────────────────────┘ │ │  │
│                   │  └─────────────────────────────────────┘ │  │
│                   └──────────────────────────────────────────┘  │
│                              │ IRSA                              │
│               ┌──────────────┼──────────────────┐               │
│               ▼              ▼                  ▼               │
│          ┌─────────┐   ┌──────────┐    ┌────────────┐          │
│          │   S3    │   │ DynamoDB │    │  Bedrock   │          │
│          │ Buckets │   │  Tables  │    │  (Claude)  │          │
│          └─────────┘   └──────────┘    └────────────┘          │
│               │                                                  │
│          ┌─────────┐   ┌──────────┐    ┌────────────┐          │
│          │   ECR   │   │ Cognito  │    │    SES     │          │
│          │ (Images)│   │  (Auth)  │    │  (Email)   │          │
│          └─────────┘   └──────────┘    └────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

**Components:**
- **EKS Cluster** - Runs the Flask API (2 replicas) + cron workers
- **ALB** - Internet-facing load balancer via AWS Load Balancer Controller
- **ECR** - Container image registry for the backend Docker image
- **S3** - Audio files, transcripts/summaries, frontend assets
- **DynamoDB** - Podcast metadata, episode tracking, distribution lists
- **Cognito** - Admin user authentication
- **Bedrock** - Claude AI for transcript summarisation
- **SES** - Email digest delivery
- **IRSA** - Fine-grained IAM permissions for pods

---

## Prerequisites

| Tool | Minimum Version | Installation |
|------|----------------|-------------|
| AWS CLI | v2.x | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Terraform | >= 1.5.0 | [Install guide](https://developer.hashicorp.com/terraform/install) |
| kubectl | >= 1.28 | [Install guide](https://kubernetes.io/docs/tasks/tools/) |
| Docker | >= 24.0 | [Install guide](https://docs.docker.com/get-docker/) |
| Helm | >= 3.12 | [Install guide](https://helm.sh/docs/intro/install/) |
| jq | any | `apt install jq` / `brew install jq` |

**AWS Requirements:**
- Root or admin-level AWS credentials configured
- Amazon Bedrock access enabled for Claude models in your region
- Sufficient service quotas (EKS clusters, EC2 instances, NAT gateways)

---

## Deployment Steps

### Step 0: Check Prerequisites

```bash
cd nyt-pod-scraper/deploy/scripts
chmod +x *.sh
./00-prerequisites.sh
```

This verifies all tools are installed, AWS credentials are valid, and Docker is running. Fix any issues before proceeding.

---

### Step 1: Set Up IAM Users & Permissions

Run the IAM setup script with root/admin credentials. This creates:
- Three IAM users with appropriate access levels
- IAM groups and policies
- Terraform state backend (S3 bucket + DynamoDB lock table)

```bash
# Set your region (default: eu-west-2)
export AWS_REGION=eu-west-2

# Run the IAM setup
./01-iam-setup.sh
```

**What gets created:**

| IAM User | Purpose | Access Level |
|----------|---------|-------------|
| `pod-monitor-deployer` | Initial deployment + Terraform | Full deploy (EKS, VPC, IAM roles, S3, DynamoDB, ECR, Cognito, SES) |
| `pod-monitor-operator` | Day-to-day operations | ECR push, kubectl, S3 data, DynamoDB CRUD, SES, Cognito admin |
| `pod-monitor-readonly` | Monitoring dashboards | Read-only on EKS, S3, DynamoDB, CloudWatch, ECR |

**Access keys** are saved to `./iam-credentials/`. Distribute securely.

Switch to the deployer profile for subsequent steps:

```bash
# Configure AWS CLI profile for the deployer
aws configure --profile pod-monitor-deployer
# Enter the access key and secret from iam-credentials/pod-monitor-deployer.env

# Use this profile for all following commands
export AWS_PROFILE=pod-monitor-deployer
```

---

### Step 2: Deploy Infrastructure with Terraform

This provisions the EKS cluster, VPC, ECR, S3 buckets, DynamoDB tables, Cognito, and SES.

```bash
# Preview what will be created (recommended first)
ADMIN_EMAIL="your-email@bmj.com" \
SENDER_EMAIL="pod-monitor@bmj.com" \
./02-terraform-init.sh plan

# Deploy (takes ~15-20 minutes for EKS)
ADMIN_EMAIL="your-email@bmj.com" \
SENDER_EMAIL="pod-monitor@bmj.com" \
./02-terraform-init.sh
```

The script will:
1. Initialize Terraform providers
2. Create all AWS resources
3. Configure `kubectl` to point at the new EKS cluster
4. Save Terraform outputs to `terraform-outputs.json`

**Expected output at the end:**
```
--- Cluster Status ---
Kubernetes control plane is running at https://xxxxx.gr7.eu-west-2.eks.amazonaws.com
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-100-xxx.ec2.internal   Ready    <none>   5m    v1.29.x
ip-10-0-101-xxx.ec2.internal   Ready    <none>   5m    v1.29.x
```

> **Note:** After deployment, verify the SES sender email. AWS sends a verification
> email to the sender address — click the link to verify it before digest emails can work.

---

### Step 3: Build & Push Docker Image

Build the backend container and push it to ECR:

```bash
./03-build-and-push.sh
```

This:
1. Authenticates Docker to ECR
2. Builds the multi-stage Docker image (Python 3.12 + Flask + ffmpeg)
3. Tags with `latest` and the current git commit SHA
4. Pushes both tags to ECR

To build a specific version:
```bash
./03-build-and-push.sh v1.0.0
```

---

### Step 4: Deploy to Kubernetes

Apply all Kubernetes manifests with values from Terraform:

```bash
./04-deploy-k8s.sh
```

This deploys:
- **Namespace** (`pod-monitor`)
- **Service Account** (with IRSA annotation for AWS access)
- **ConfigMap** (AWS resource names, region, model config)
- **Deployment** (Flask API, 2 replicas, rolling updates)
- **Service** (ClusterIP)
- **Ingress** (ALB, internet-facing)
- **CronJobs** (scraper every 6h, daily digest 8am, weekly digest Monday 8am)
- **HPA** (auto-scale 2-6 replicas based on CPU/memory)

Wait for the ALB to provision (~2-3 minutes). The script will print the URL:
```
  Admin App:  http://pod-monitor-xxx.eu-west-2.elb.amazonaws.com
  API:        http://pod-monitor-xxx.eu-west-2.elb.amazonaws.com/api
```

---

### Step 5: Add Three Science Podcasts

Add real science podcasts and trigger the first scrape:

```bash
./05-add-podcasts.sh
```

This adds three freely available podcast RSS feeds:

| # | Podcast | RSS Feed | Category |
|---|---------|----------|----------|
| 1 | **Nature Podcast** | `feeds.nature.com/nature/podcast/current` | Science & Research |
| 2 | **The Lancet Voice** | `feeds.acast.com/public/shows/the-lancet-voice` | Medical Science |
| 3 | **Science Friday** | `feeds.megaphone.fm/sciencefriday` | General Science |

After adding podcasts, the script triggers an initial scrape to fetch the latest episodes from each feed.

You can also add podcasts manually via the admin UI or API:
```bash
curl -X POST http://<ALB_URL>/api/podcasts \
  -H "Content-Type: application/json" \
  -d '{
    "name": "BMJ Talk Medicine",
    "url": "https://feeds.bmj.com/talk-medicine",
    "category": "Clinical Medicine",
    "active": true
  }'
```

---

### Step 6: Validate the Deployment

Run the comprehensive validation suite:

```bash
./06-validate.sh
```

This checks:
1. **Kubernetes Cluster** - Nodes ready, kubectl connected
2. **Namespace & Pods** - Pods running, deployment replicas healthy
3. **Services & Ingress** - ClusterIP service, ALB provisioned
4. **API Endpoints** - `/api/health`, `/api/podcasts`, `/api/config`, admin SPA
5. **CronJobs** - Scraper, daily digest, weekly digest all scheduled
6. **Autoscaling** - HPA configured with min/max replicas
7. **AWS Resources** - S3 buckets, DynamoDB tables, Cognito pool accessible

**Expected output:**
```
  Validation Summary
  Total checks: 20
  Passed:       20
  Failed:       0
  Warnings:     0

  STATUS: ALL CHECKS PASSED
```

---

## Verifying It Works End-to-End

After deployment and adding podcasts, verify the full pipeline:

### 1. Check the Admin Dashboard

Open the ALB URL in your browser:
```
http://pod-monitor-xxx.eu-west-2.elb.amazonaws.com
```

You should see:
- Dashboard with podcast count and episode stats
- Three science podcasts listed under "Podcasts"
- Recent episodes from each feed under "Episodes"

### 2. Verify Episodes Were Scraped

```bash
# Check episodes via API
curl http://<ALB_URL>/api/podcasts | jq '.'

# Check for downloaded episodes
curl http://<ALB_URL>/api/episodes | jq '.[] | {podcast: .podcast_name, title: .title, date: .published}'
```

### 3. Manually Trigger a Scrape

```bash
# Trigger scrape for all podcasts
curl -X POST http://<ALB_URL>/api/scrape-all | jq '.'
```

### 4. Check CronJob Execution

```bash
# View CronJob status
kubectl get cronjobs -n pod-monitor

# Check if any jobs have run
kubectl get jobs -n pod-monitor

# View logs from the last scraper run
kubectl logs -l component=scraper -n pod-monitor --tail=50
```

### 5. View Logs

```bash
# API pod logs
kubectl logs -l component=api -n pod-monitor --tail=100 -f

# Scraper CronJob logs
kubectl logs -l component=scraper -n pod-monitor --tail=50
```

### 6. Verify AWS Resources Have Data

```bash
# Check S3 audio bucket for downloaded files
aws s3 ls s3://pod-monitor-dev-audio-<account-id>/ --recursive --human-readable

# Check S3 data bucket for transcripts/summaries
aws s3 ls s3://pod-monitor-dev-data-<account-id>/ --recursive --human-readable

# Check DynamoDB for podcast records
aws dynamodb scan --table-name pod-monitor-dev-podcasts --region eu-west-2
```

---

## Directory Structure

```
nyt-pod-scraper/deploy/
├── DEPLOYMENT_GUIDE.md          # This file
├── terraform-outputs.json       # Generated by Step 2 (gitignored)
│
├── docker/
│   └── Dockerfile               # Backend container (Python 3.12 + Flask + ffmpeg)
│
├── terraform/
│   ├── main.tf                  # EKS, VPC, ECR, S3, DynamoDB, SES, Cognito, IRSA, ALB Controller
│   ├── variables.tf             # Input variables with validation
│   ├── outputs.tf               # Outputs for k8s manifest templating
│   └── environments/
│       └── dev.tfvars           # Dev environment defaults
│
├── k8s/
│   ├── namespace.yaml           # pod-monitor namespace
│   ├── service-account.yaml     # IRSA-annotated service account
│   ├── configmap.yaml           # AWS resource names / app config
│   ├── deployment.yaml          # Flask API (2 replicas, rolling update)
│   ├── service.yaml             # ClusterIP service
│   ├── ingress.yaml             # ALB ingress (internet-facing)
│   ├── cronjob-scraper.yaml     # Scraper (6h) + daily/weekly digest crons
│   └── hpa.yaml                 # Horizontal Pod Autoscaler (2-6 pods)
│
└── scripts/
    ├── 00-prerequisites.sh      # Check all required tools
    ├── 01-iam-setup.sh          # Create IAM users, groups, policies, TF state backend
    ├── 02-terraform-init.sh     # Terraform init + apply (EKS + infra)
    ├── 03-build-and-push.sh     # Build Docker image + push to ECR
    ├── 04-deploy-k8s.sh         # Apply k8s manifests with TF output substitution
    ├── 05-add-podcasts.sh       # Add 3 science podcasts + trigger scrape
    ├── 06-validate.sh           # Comprehensive deployment validation
    └── teardown.sh              # Destroy everything (irreversible)
```

---

## Cost Estimates (Dev Environment)

| Service | Monthly Cost (approx) | Notes |
|---------|----------------------|-------|
| EKS Cluster | $73 | Control plane ($0.10/hr) |
| EC2 (2x t3.medium) | $60 | Worker nodes |
| NAT Gateway | $32 | + data transfer |
| ALB | $16 | + LCU charges |
| S3 | $1-5 | Depends on audio volume |
| DynamoDB | $1-5 | On-demand, low volume |
| ECR | $1 | Image storage |
| Bedrock (Claude) | $5-50 | Depends on transcript volume |
| **Total** | **~$190-240/mo** | Dev with 3 podcasts |

> For cost savings in dev: use `t3.small` nodes, single-AZ, reduce node count to 1.

---

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n pod-monitor
# Usually: insufficient resources. Scale up nodes or use larger instance type.
```

### ALB not provisioning
```bash
kubectl describe ingress pod-monitor-ingress -n pod-monitor
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
# Check: subnets tagged correctly, security group allows traffic
```

### IRSA not working (pods can't access S3/DynamoDB)
```bash
# Verify service account annotation
kubectl get sa pod-monitor-sa -n pod-monitor -o yaml
# Verify OIDC provider
aws iam list-open-id-connect-providers
```

### ECR push fails
```bash
# Re-authenticate
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-2.amazonaws.com
```

### SES emails not sending
```bash
# Check verification status
aws ses get-identity-verification-attributes --identities <sender-email>
# New SES accounts are in sandbox mode - request production access
```

---

## Cleanup

To destroy all infrastructure:

```bash
./scripts/teardown.sh
```

This removes all Kubernetes resources then runs `terraform destroy` to delete
all AWS resources. The IAM users/groups created by `01-iam-setup.sh` are NOT
deleted (remove manually if needed).

To also remove the Terraform state backend:
```bash
aws s3 rb s3://pod-monitor-terraform-state-<account-id> --force
aws dynamodb delete-table --table-name pod-monitor-terraform-locks
```
