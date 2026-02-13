# Wiz Technical Exercise V4

This repository contains the implementation of the **Wiz Technical Exercise V4** for a Solutions Engineer role. It demonstrates building and deploying a two-tier web application on Google Cloud Platform (GCP) with intentional security misconfigurations, automated CI/CD with security scanning, and GCP-native security tooling to detect those weaknesses.

## Overview

- **Application**: Containerized todo app running on GKE, backed by MongoDB on a Compute Engine VM.
- **Infrastructure**: Defined as code with Terraform (VPC, GKE, VM, Cloud Storage, firewall rules).
- **CI/CD**: GitHub Actions pipelines for infrastructure and application deployment with strict security gating (IaC and container scanning).
- **Security**: Intentional misconfigurations are implemented for demonstration; GCP Security Command Center, Cloud Audit Logs, and other tools are used to detect them.

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| `terraform/` | Terraform configuration for GCP infrastructure |
| `app/` | Sample todo application source and Dockerfile |
| `kubernetes/` | Kubernetes manifests (Deployment, Service, Ingress) |
| `scripts/` | Automation scripts (e.g. GCP bootstrap, backups) |
| `.github/workflows/` | GitHub Actions CI/CD workflows |
| `docs/` | Documentation and setup guides |

## Prerequisites

- **GCP**: CloudLabs project (or equivalent) with billing enabled.
- **Local tools**: `gcloud`, Terraform, `kubectl`, Docker.
- **GitHub**: Account for repository and CI/CD.

## Quick Start

1. **GCP setup**  
   For the **wizdemo-487311** project, run (after `gcloud auth login`):

   ```bash
   ./scripts/setup-wizdemo-project.sh
   ```

   This enables APIs, creates the automation service account and state bucket, and writes the key to `.keys/wiz-exercise-automation-key.json`. For other projects, set `GCP_PROJECT_ID` and run [scripts/gcp-bootstrap.sh](scripts/gcp-bootstrap.sh). See [docs/GCP_BOOTSTRAP.md](docs/GCP_BOOTSTRAP.md) for details.

2. **GitHub**  
   Create the repo (e.g. from this clone), push, then enable branch protection, required reviews, status checks, Dependabot, and secret scanning. See [docs/GITHUB_SETUP.md](docs/GITHUB_SETUP.md).

3. **Infrastructure**  
   In the `terraform/` directory, configure the GCS backend and run `terraform init` and `terraform apply`. See [docs/INFRASTRUCTURE_DEPLOYMENT.md](docs/INFRASTRUCTURE_DEPLOYMENT.md) for the manual deployment phase.

4. **Application**  
   Build the todo app image, push to a container registry, and deploy to GKE using manifests in `kubernetes/` (see later tickets).

## Security Controls (Repo)

- Branch protection on the default branch  
- Required PR reviews before merge  
- Required status checks (CI/CD and scans); see [docs/CI_CD_PIPELINES.md](docs/CI_CD_PIPELINES.md)  
- Secret scanning enabled (public repo or GitHub Advanced Security)  
- Dependabot alerts enabled  

## Intentional Misconfigurations (Demo)

These are introduced for the exercise and documented in code:

- VM: outdated OS, SSH open to internet, overly permissive IAM  
- Cloud Storage: bucket with public read/list  
- Kubernetes: application workload with cluster-admin role  

## Documentation

- [GCP Bootstrap](docs/GCP_BOOTSTRAP.md) – Enable APIs, service account, Terraform state bucket  
- [GitHub Setup](docs/GITHUB_SETUP.md) – Repo creation and security controls  
- [Infrastructure Deployment](docs/INFRASTRUCTURE_DEPLOYMENT.md) – Manual Terraform deploy (VPC, GKE, VM, bucket)  
- [Flow 1 Validation](docs/VALIDATION_FLOW1.md) – Initial setup checklist  
- [Flow 2 Validation](docs/VALIDATION_FLOW2.md) – Infrastructure deployment checklist  

## License

For use as part of the Wiz Technical Exercise only.
