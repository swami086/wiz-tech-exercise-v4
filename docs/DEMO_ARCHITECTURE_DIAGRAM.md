# Demo Architecture – High-Level Mermaid Diagram

## Codebase-accurate high-level diagram

For a **single diagram that matches the actual Terraform, scripts, and workflows** in this repo (entry points, CI/CD, GCP layout, deployment paths), see:

- **[demo-setup-high-level.mmd](demo-setup-high-level.mmd)** – High-level demo setup with Terraform file reference table and deployment modes.

The diagrams below are the original narrative/flow views; the linked file is kept in sync with the codebase.

---

## Rendered Images (for blog posts)

| Diagram | File | Description |
|---------|------|-------------|
| Main architecture | [demo-architecture.png](demo-architecture.png) | Full component overview with demo entry points, DevSecOps, infrastructure, and security |
| Simplified flow | [demo-flow-simple.png](demo-flow-simple.png) | Developer → CI Pipeline → GCP flow |

---

```mermaid
flowchart TB
    subgraph EntryPoints["Demo Entry Points"]
        WIZ["wiz-exercise-demo-end-to-end.sh<br/>Full validation (4 phases)"]
        CICD["demo-cicd-end-to-end.sh<br/>CI/CD flow demo"]
        IAC["showcase-iac-requirements.sh<br/>IaC validation"]
        PR["create-demo-pr-vulnerabilities.sh<br/>PR vulnerability showcase"]
        TF["terraform-destroy-recreate.sh<br/>Lifecycle (destroy → recreate)"]
    end

    subgraph DevSecOps["DevSecOps"]
        direction TB
        VCS[("VCS (GitHub)")]
        subgraph CI["CI/CD Pipelines"]
            P1["Phase 1 Gates<br/>terraform-validate | container-scan | deploy-gate"]
            TRIVY["Trivy scan<br/>CRITICAL/HIGH gate"]
            DEPLOY["Deploy workflow<br/>Build & push to Artifact Registry"]
        end
        BP["Branch protection<br/>Required status checks"]
    end

    subgraph Infra["Infrastructure (Terraform)"]
        direction TB
        VM["MongoDB VM<br/>Outdated Linux · SSH public · compute.admin IAM"]
        MONGO[("MongoDB 4.4<br/>K8s-only · Auth · Daily backup")]
        BUCKET[("Backup Bucket<br/>Public read/list")]
        GKE["GKE Cluster<br/>Private subnet"]
        ARGO["Argo CD<br/>(optional GitOps)"]
    end

    subgraph App["Application"]
        TASKY["Tasky Web App<br/>wizexercise.txt · MONGODB_URI"]
        LB["Ingress / Load Balancer"]
        K8S["Kubernetes<br/>cluster-admin (intentional)"]
    end

    subgraph Security["Cloud Native Security"]
        AL["Audit logs<br/>Data Access"]
        OP["Org Policy<br/>requireOsLogin (preventative)"]
        MA["Monitoring Alerts<br/>bucket public, firewall (detective)"]
    end

    %% Demo flows
    WIZ --> Infra
    WIZ --> App
    WIZ --> Security
    CICD --> CI
    CICD --> DEPLOY
    IAC --> Infra
    IAC --> App
    PR --> VCS
    PR --> P1
    TF --> Infra

    %% CI/CD flow
    VCS --> P1
    P1 --> TRIVY
    P1 --> BP
    BP --> DEPLOY
    DEPLOY --> GKE
    DEPLOY --> ARGO

    %% Infrastructure relationships
    VM --> MONGO
    MONGO --> BUCKET
    GKE --> TASKY
    TASKY --> MONGO
    TASKY --> LB
    TASKY --> K8S
    ARGO --> GKE

    %% Security
    Infra --> AL
    Infra --> OP
    Infra --> MA
```

## Simplified Flow (End-to-End)

```mermaid
flowchart LR
    subgraph Developer
        CODE[Code + IaC]
    end

    subgraph CI["CI Pipeline"]
        TV[Terraform Validate]
        CS[Container Scan]
        DG[Deploy Gate]
    end

    subgraph GCP["GCP"]
        TF[Terraform Apply]
        GKE[GKE + Tasky]
        VM[MongoDB VM]
    end

    CODE --> TV --> TF
    CODE --> CS --> DG
    DG --> GKE
    TF --> VM
    TF --> GKE
    GKE --> VM
```

## Demo Phases (wiz-exercise-demo-end-to-end.sh)

```mermaid
flowchart TB
    P0["Phase 0: Prerequisites<br/>gcloud, terraform, kubectl, GCP_PROJECT_ID"]
    P1["Phase 1: VM + MongoDB<br/>Outdated Linux · SSH public · permissive IAM · backup · bucket public"]
    P2["Phase 2: Web App on K8s<br/>Private subnet · MONGODB_URI · wizexercise.txt · cluster-admin · Ingress"]
    P3["Phase 3: DevSecOps<br/>VCS · CI/CD pipelines · IaC + container scanning"]
    P4["Phase 4: Cloud Native Security<br/>Audit logs · Org Policy · Monitoring alerts"]

    P0 --> P1 --> P2 --> P3 --> P4
```
