# editor-prompt-tool_eks

This repository contains Kubernetes manifests and Kustomize overlays for deploying the **editor-prompt-tool** application to EKS (Amazon Elastic Kubernetes Service). It supports both development (`dev`) and production/live (`live`) environments, with environment-specific configuration, secrets, and deployment options.

## Repository Structure

```
editor-prompt-tool/
  base/         # Base Kubernetes manifests (Deployment, Service, Ingress, etc.)
  overlays/
    dev/        # Development environment overlays and patches
    live/       # Production/live environment overlays and patches
.gitignore
README.md
```

### Base Manifests

Located in [`editor-prompt-tool/base/`](editor-prompt-tool/base/kustomization.yaml), these define the core Kubernetes resources:
- Deployment
- Service
- Ingress
- ServiceAccount
- Job (for DB migrations)
- Instrumentation (OpenTelemetry)
- ArgoCD Application

### Overlays

Environment-specific overlays in [`editor-prompt-tool/overlays/dev/`](editor-prompt-tool/overlays/dev/kustomization.yaml) and [`editor-prompt-tool/overlays/live/`](editor-prompt-tool/overlays/live/kustomization.yaml) customize the base manifests using:
- Patches (for environment variables, ingress, service, etc.)
- SealedSecrets for sensitive data
- Image tags and replica counts
- ServiceAccount/IAM role bindings (dev only)
- Hostname and certificate configuration

### ArgoCD & ApplicationSet

- [`base/argocd.yaml`](editor-prompt-tool/base/argocd.yaml): Defines the ArgoCD Application for the dev environment.
- [`overlays/dev/application-set.yaml`](editor-prompt-tool/overlays/dev/application-set.yaml) and [`overlays/live/application-set.yaml`](editor-prompt-tool/overlays/live/application-set.yaml): Define ArgoCD ApplicationSets for preview environments based on GitHub pull requests.

## Deployment

### Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/)
- [Sealed Secrets Controller](https://github.com/bitnami-labs/sealed-secrets)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)

### Deploy to Dev or Live

To build and apply the manifests for a specific environment:

```sh
# For dev
kustomize build editor-prompt-tool/overlays/dev | kubectl apply -f -

# For live
kustomize build editor-prompt-tool/overlays/live | kubectl apply -f -
```

Or use ArgoCD to sync the application.

## Secrets Management

Secrets are managed using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). Encrypted secrets are stored in [`sealed-secrets.yaml`](editor-prompt-tool/overlays/dev/sealed-secrets.yaml) and [`sealed-secrets.yaml`](editor-prompt-tool/overlays/live/sealed-secrets.yaml).

## Customization

- **Environment variables**: Set via `env.yaml` overlays.
- **Ingress and Service hostnames**: Patched and replaced environment.
- **AWS IAM roles**: Patched in dev via `serviceaccount-patch.yaml`.
- **Image tags**: Set in the `images` section of each overlay's `kustomization.yaml`.

## Notes

- The base manifests are generic; all environment-specific configuration is handled via overlays.
- The repository is designed for GitOps workflows with ArgoCD and supports preview environments for pull requests.

---

For more details, see the individual manifest files in the [`editor-prompt-tool`](editor-prompt-tool/) directory.