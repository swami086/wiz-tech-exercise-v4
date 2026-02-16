# Demo scripts

Run these from the **repository root**.

| Script | Purpose |
|--------|---------|
| **create-demo-pr-vulnerabilities.sh** | Create a PR with an intentional vulnerable base image (Alpine 3.17.0) to showcase Trivy scanning and PR checks. Use `--post-merge-demo` after merging to show Argo CD deploying the app. |
| **demo-cicd-end-to-end.sh** | Full CI/CD demo: prerequisites → local CI gates (Terraform, container build, Trivy) → optional GitHub → build/push → deployment verification. |
| **wiz-exercise-demo-end-to-end.sh** | End-to-end validation of the Wiz exercise environment (VM/MongoDB, K8s app, DevSecOps, cloud native security). Use `PROVISION=1` to run Terraform apply first. |
| **showcase-iac-requirements.sh** | IaC showcase: validates every Terraform requirement (VM, MongoDB, backup bucket, K8s app, wizexercise.txt, Ingress, data in DB). Use after any `terraform apply`; supports `--apply` or `--destroy-apply` to run Terraform then validate. |
| **terraform-destroy-recreate.sh** | Terraform full lifecycle: validate → plan → destroy → plan → apply. Use `--no-destroy` for validate + plan only; `--yes` to skip destroy confirmation; `--skip-showcase` to skip IaC showcase after apply. |
| **run-iac-pipeline.sh** | Run the IaC Deploy pipeline: trigger the GitHub Actions workflow (default) or run validate/apply locally with `--local` and `--local --apply`. Use when you create or change Terraform infra. |

See [DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md](../docs/DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md) for the presentation narrative and options.
