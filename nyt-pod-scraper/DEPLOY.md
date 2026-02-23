# BMJ Pod Monitor - Deployment Guide

Step-by-step instructions for deploying the Pod Monitor podcast intelligence
platform. Two deployment options are available:

- **Option A: Local (Mac/Linux)** -- Run locally for development and testing
- **Option B: AWS (EKS)** -- Full production deployment on AWS

---

## Table of Contents

1. [Local Deployment (Mac)](#option-a-local-deployment-mac)
2. [AWS Deployment (EKS)](#option-b-aws-deployment-eks)
3. [Architecture](#architecture)
4. [Troubleshooting](#troubleshooting)
5. [Cleanup](#cleanup)

---

## Option A: Local Deployment (Mac)

Run the full application on your Mac for development and testing.
No AWS account required. Data is stored on the local filesystem.

### Prerequisites

| Tool       | Install command             |
|------------|-----------------------------|
| Python 3.10+ | `brew install python3`    |
| Docker (optional) | [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/) |

### Step 1: Clone the repository

```bash
git clone <repo-url>
cd bmj-ai-rapid-prototype/nyt-pod-scraper
```

### Step 2: (Optional) Configure an LLM API key

The app works without an LLM key -- you just won't get AI-powered
transcription and summarisation. To enable AI features, set one of:

```bash
# Pick ONE provider:
export ANTHROPIC_API_KEY=sk-ant-xxx   # Anthropic Claude
export OPENAI_API_KEY=sk-xxx          # OpenAI GPT
export GOOGLE_API_KEY=AIza-xxx        # Google Gemini
```

Or copy the example env file and edit it:

```bash
cp backend/.env.example backend/.env
# Edit backend/.env with your API key
```

### Step 3: Start the application

**Option 3a: Python virtual environment (recommended for development)**

```bash
./scripts/local-run.sh --seed
```

This will:
1. Create a Python virtual environment
2. Install all dependencies
3. Seed realistic demo data (4 podcasts, 10 episodes with summaries)
4. Start the Flask server on `http://localhost:5001`

**Option 3b: Docker Compose (closer to production)**

```bash
./scripts/local-run.sh --docker --seed
```

Or directly with docker compose:

```bash
docker compose up --build
```

### Step 4: Open the admin app

Open your browser to: **http://localhost:5001**

You should see the Pod Monitor dashboard with:
- 4 demo podcasts (HealthWatch Weekly, Medical Myths Debunked, etc.)
- 10 episodes with transcripts, summaries, and themes
- Distribution lists for daily and weekly email digests

### Step 5: Explore the API

```bash
# List all podcasts
curl http://localhost:5001/api/podcasts | python3 -m json.tool

# List episodes for a podcast
curl http://localhost:5001/api/podcasts/pod_healthwatch/episodes | python3 -m json.tool

# Preview the daily digest email
curl http://localhost:5001/api/email/daily/preview | python3 -m json.tool

# Get current configuration
curl http://localhost:5001/api/config | python3 -m json.tool
```

### Stopping the local server

- **Python mode**: Press `Ctrl+C`
- **Docker mode**: `docker compose down`

---

## Option B: AWS Deployment (EKS)

Full production deployment on AWS using EKS, S3, DynamoDB, Cognito, SES,
and Bedrock. Turnkey: provide AWS credentials and run one script.

### Prerequisites

| Tool | Minimum Version | Install (macOS) |
|------|----------------|-----------------|
| AWS CLI | v2.x | `brew install awscli` |
| Terraform | >= 1.5.0 | `brew install terraform` |
| kubectl | >= 1.28 | `brew install kubectl` |
| Docker | >= 24.0 | [Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| Helm | >= 3.12 | `brew install helm` |
| jq | any | `brew install jq` |

### Step 1: Configure AWS credentials

You need an AWS account with admin-level access. Export your credentials:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=abc123...
export AWS_REGION=eu-west-2            # London (default)
```

Verify access:

```bash
aws sts get-caller-identity
```

### Step 2: Set required environment variables

```bash
export ADMIN_EMAIL="your-email@bmj.com"     # Cognito admin account
export SENDER_EMAIL="pod-monitor@bmj.com"   # SES sender identity
```

### Step 3: Run the turnkey deployment

```bash
./scripts/deploy-aws.sh
```

The script runs 6 steps automatically:

| Step | What it does |
|------|-------------|
| 1 | Creates VPC, EKS cluster, ECR repository (`terraform/eks/`) |
| 2 | Creates S3 buckets, DynamoDB tables, Cognito, SES, IRSA role (`terraform/common/`) |
| 3 | Builds the Docker image and pushes to ECR |
| 4 | Deploys K8s manifests via Kustomize (`k8s/overlays/dev/`) |
| 5 | Seeds demo data into the running pod |
| 6 | Validates the deployment and prints the ALB URL |

When complete, you'll see output like:

```
=============================================
  BMJ Pod Monitor - Deployment Complete
=============================================

  Cluster:    pod-monitor-dev
  Region:     eu-west-2
  Account:    123456789012

  Admin App:  http://pod-monitor-xxx.eu-west-2.elb.amazonaws.com
  API:        http://pod-monitor-xxx.eu-west-2.elb.amazonaws.com/api/podcasts
```

### Step 4: Verify the SES sender email

AWS sends a verification email to the sender address. Check your inbox
and click the verification link. Until verified, the app cannot send
email digests.

### Step 5: Open the admin app

Navigate to the ALB URL printed at the end of the deployment.
If the ALB isn't ready yet, check its status:

```bash
kubectl get ingress -n pod-monitor
```

### Step 6: (Optional) Add real podcasts

```bash
ALB_URL=$(kubectl get ingress pod-monitor -n pod-monitor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -X POST "http://$ALB_URL/api/podcasts" \
  -H "Content-Type: application/json" \
  -d '{"name": "Nature Podcast", "feed_url": "https://feeds.nature.com/nature/podcast/current", "category": "Science"}'

curl -X POST "http://$ALB_URL/api/podcasts" \
  -H "Content-Type: application/json" \
  -d '{"name": "The Lancet Voice", "feed_url": "https://feeds.acast.com/public/shows/the-lancet-voice", "category": "Medical Science"}'
```

---

## Architecture

### Local Mode

```
┌─────────────────────────────────────────┐
│           Your Mac (localhost:5001)       │
│                                          │
│   ┌──────────────────────────────────┐   │
│   │     Flask API + Admin SPA        │   │
│   │     (backend/app.py)             │   │
│   └──────────┬───────────────────────┘   │
│              │                            │
│   ┌──────────▼───────────────────────┐   │
│   │   Local filesystem (backend/data) │   │
│   │   - config/   - audio/            │   │
│   │   - transcripts/  - summaries/    │   │
│   └──────────────────────────────────┘   │
│                                          │
│   Optional: LLM API (OpenAI/Claude)      │
└─────────────────────────────────────────┘
```

### AWS Mode

```
┌───────────────────────────────────────────────────────────┐
│                    AWS (eu-west-2)                          │
│                                                            │
│  ┌──────────┐    ┌────────────────────────────────────┐   │
│  │   ALB    │───▶│         EKS Cluster                 │   │
│  │(Internet)│    │  ┌──────────────────────────────┐  │   │
│  └──────────┘    │  │  pod-monitor namespace        │  │   │
│                  │  │                               │  │   │
│                  │  │  ┌─────────┐  ┌─────────┐    │  │   │
│                  │  │  │ API Pod │  │ API Pod │    │  │   │
│                  │  │  │ (Flask) │  │(replica)│    │  │   │
│                  │  │  └────┬────┘  └────┬────┘    │  │   │
│                  │  │       │    IRSA     │         │  │   │
│                  │  │  ┌────┴────────────┴──────┐  │  │   │
│                  │  │  │  CronJobs:             │  │  │   │
│                  │  │  │  - scraper  (6h)       │  │  │   │
│                  │  │  │  - daily   (8am)       │  │  │   │
│                  │  │  │  - weekly  (Mon 8am)   │  │  │   │
│                  │  │  └────────────────────────┘  │  │   │
│                  │  └──────────────────────────────┘  │   │
│                  └────────────────────────────────────┘   │
│                              │ IRSA                        │
│              ┌───────────────┼────────────────┐           │
│              ▼               ▼                ▼           │
│         ┌────────┐    ┌──────────┐    ┌──────────┐       │
│         │   S3   │    │ DynamoDB │    │ Bedrock  │       │
│         │Buckets │    │  Tables  │    │ (Claude) │       │
│         └────────┘    └──────────┘    └──────────┘       │
│              │                                            │
│         ┌────────┐    ┌──────────┐    ┌──────────┐       │
│         │  ECR   │    │ Cognito  │    │   SES    │       │
│         │(Images)│    │  (Auth)  │    │ (Email)  │       │
│         └────────┘    └──────────┘    └──────────┘       │
└───────────────────────────────────────────────────────────┘
```

### Project Structure

```
nyt-pod-scraper/
├── DEPLOY.md                    # This file
├── docker-compose.yaml          # Local Docker Compose
│
├── backend/                     # Flask API + processing modules
│   ├── app.py                   # API server entry point
│   ├── config.py                # Configuration management
│   ├── scraper.py               # RSS feed scraper
│   ├── transcriber.py           # Audio transcription
│   ├── summarizer.py            # LLM summarisation
│   ├── email_generator.py       # Email digest rendering
│   ├── storage.py               # Abstracted storage layer
│   ├── requirements.txt         # Python dependencies
│   └── .env.example             # Example environment variables
│
├── admin-app/                   # Frontend SPA (HTML/JS)
│
├── terraform/                   # Infrastructure as Code (BMJ patterns)
│   ├── common/                  # S3, DynamoDB, IAM/IRSA, Cognito, SES
│   │   ├── backends.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── s3.tf
│   │   ├── dynamodb.tf
│   │   ├── iam.tf
│   │   ├── cognito.tf
│   │   ├── ses.tf
│   │   ├── outputs.tf
│   │   └── params/
│   │       ├── dev/
│   │       │   ├── backends.tfvars
│   │       │   └── params.tfvars
│   │       └── live/
│   │           ├── backends.tfvars
│   │           └── params.tfvars
│   └── eks/                     # VPC, EKS Cluster, ECR
│       ├── backends.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── params/
│           ├── dev/
│           │   ├── backends.tfvars
│           │   └── params.tfvars
│           └── live/
│               ├── backends.tfvars
│               └── params.tfvars
│
├── k8s/                         # Kubernetes manifests (Kustomize)
│   ├── base/                    # Common manifests
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml
│   │   ├── cronjob-scraper.yaml
│   │   └── hpa.yaml
│   └── overlays/                # Per-environment patches
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   ├── env-patch.yaml
│       │   ├── serviceaccount-patch.yaml
│       │   └── replicas-patch.yaml
│       └── live/
│           ├── kustomization.yaml
│           ├── env-patch.yaml
│           ├── serviceaccount-patch.yaml
│           └── replicas-patch.yaml
│
├── deploy/                      # Docker & deployment scripts
│   └── docker/
│       └── Dockerfile
│
└── scripts/                     # Automation scripts
    ├── deploy-aws.sh            # Turnkey AWS deployment
    ├── teardown-aws.sh          # Destroy all AWS resources
    └── local-run.sh             # Local development runner
```

---

## Terraform Patterns

The Terraform code follows BMJ conventions from `editor-prompt-tool_tf-main`:

| Pattern | Implementation |
|---------|---------------|
| Modular directory structure | `terraform/common/` and `terraform/eks/` as separate root modules |
| S3 backend with external config | `backend "s3" {}` in `backends.tf`, vars in `params/{env}/backends.tfvars` |
| Standard BMJ variables | `accountid`, `costcentre`, `creator`, `scope`, `stack`, `product`, `project`, `namespace` |
| Default tags | `CostCentre`, `Creator`, `Environment`, `Product`, `Project`, `Region`, `Scope`, `Stack`, `Namespace` |
| Per-environment tfvars | `params/dev/params.tfvars` and `params/live/params.tfvars` |
| `aws_iam_policy_document` data sources | Used for all IAM policies (not inline `jsonencode`) |
| IRSA with OIDC | Matches `editor-prompt-tool_tf-main/terraform/common/role.tf` pattern |
| S3 with versioning + encryption + public access block | Matches `editor-prompt-tool_tf-main/terraform/common/s3.tf` pattern |

The K8s manifests follow `editor-prompt-tool_eks-main` Kustomize patterns:

| Pattern | Implementation |
|---------|---------------|
| Kustomize base + overlays | `k8s/base/` with `k8s/overlays/{dev,live}/` |
| Standard labels | `app.kubernetes.io/name`, `app`, `team`, `CostCentre`, `project`, `product` |
| ServiceAccount for IRSA | `serviceaccount.yaml` with `eks.amazonaws.com/role-arn` annotation |
| Health/readiness probes | On the `/api/podcasts` endpoint |
| Resource limits | Requests and limits specified for all containers |
| Topology spread | Zone-aware scheduling via `topologySpreadConstraints` |

### Running Terraform with BMJ S3 Backend

For CI/CD pipelines or when using the BMJ shared state buckets:

```bash
# EKS module
cd terraform/eks
terraform init -backend-config=params/dev/backends.tfvars
terraform plan -var-file=params/dev/params.tfvars
terraform apply -var-file=params/dev/params.tfvars

# Common module (after EKS is deployed)
cd terraform/common
terraform init -backend-config=params/dev/backends.tfvars
terraform plan -var-file=params/dev/params.tfvars
terraform apply -var-file=params/dev/params.tfvars
```

---

## Cost Estimates (AWS Dev)

| Service | Monthly Cost (approx) |
|---------|----------------------|
| EKS Cluster | $73 |
| EC2 (2x t3.medium) | $60 |
| NAT Gateway | $32 |
| ALB | $16 |
| S3 | $1-5 |
| DynamoDB | $1-5 |
| ECR | $1 |
| Bedrock (Claude) | $5-50 |
| **Total** | **~$190-240/month** |

---

## Troubleshooting

### Local: "ModuleNotFoundError"

```bash
# Ensure venv is activated
source backend/venv/bin/activate
pip install -r backend/requirements.txt
```

### Local: Port 5001 already in use

```bash
# Find and kill the process
lsof -ti:5001 | xargs kill -9
# Or use a different port
FLASK_PORT=5002 ./scripts/local-run.sh
```

### AWS: Pods stuck in Pending

```bash
kubectl describe pod <pod-name> -n pod-monitor
# Usually: insufficient resources. Check node group scaling.
```

### AWS: ALB not provisioning

```bash
kubectl describe ingress pod-monitor -n pod-monitor
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

### AWS: IRSA not working

```bash
kubectl get sa pod-monitor -n pod-monitor -o yaml
# Verify the eks.amazonaws.com/role-arn annotation is set
```

---

## Cleanup

### Local

```bash
# Docker mode
docker compose down -v

# Python mode - just Ctrl+C to stop, then optionally:
rm -rf backend/data backend/venv
```

### AWS

```bash
./scripts/teardown-aws.sh
```

This destroys all Kubernetes resources, then runs `terraform destroy` for
both the common and EKS modules. All AWS resources will be deleted.
