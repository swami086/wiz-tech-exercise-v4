# IaC in a Separate Repository (Optional)

The Terraform (IaC) pipeline can be run from a **dedicated repository** with full security scanning (tfsec, Checkov) and GitHub Actions.

## Separate repo: wiz-iac

- **Repository:** [swami086/wiz-iac](https://github.com/swami086/wiz-iac) (private).
- **Contents:** Copy of the `terraform/` directory at repo root, plus a GitHub Actions workflow that runs:
  - **validate** – Terraform init (no backend), validate, fmt check.
  - **tfsec** – IaC security scan (SARIF to Security tab).
  - **checkov** – Policy/security scan (SARIF to Security tab).
  - **terrascan** – IaC security scan (GCP policy; SARIF to Security tab).
  - **tflint** – Terraform lint and best-practice checks (SARIF to Security tab).
  - **deploy** – On push to `main`: Terraform plan and apply (with GCS backend).

## Triggering the IaC pipeline

1. **In the wiz-iac repo:** Push or open a PR to `main`, or use **Actions → IaC Deploy → Run workflow**.
2. **From this repo (or anywhere):** Using GitHub CLI:
   ```bash
   gh workflow run iac-deploy.yml --repo swami086/wiz-iac
   ```
   Or with a specific ref:
   ```bash
   gh workflow run iac-deploy.yml --repo swami086/wiz-iac --ref main
   ```

## This repo (wiz-tech-exercise-v4) unchanged

- The **`terraform/`** directory and **`.github/workflows/iac-deploy.yml`** in this repo are **unchanged**. You can continue to use them for local Terraform and for the combined CI/CD story.
- The separate repo is an **optional** way to run the IaC pipeline in isolation with dedicated security scanning and its own branch protection.

See the [wiz-iac README](https://github.com/swami086/wiz-iac) for secrets setup and local usage.
