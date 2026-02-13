# GitHub Repository Setup & Security Controls

This guide covers creating the GitHub repository from this codebase and enabling the **repository security controls** required by the Wiz Technical Exercise: branch protection, required PR reviews, required status checks, secret scanning, and Dependabot alerts.

## 1. Create the repository

- **Option A – GitHub CLI (`gh`)**

  ```bash
  gh repo create YOUR_ORG_OR_USER/wiz-tech-exercise-v4 --private --source=. --remote=origin --push
  ```

  Use `--public` if you want a public repo (needed for free secret scanning unless you have GitHub Advanced Security).

- **Option B – GitHub web**

  1. Create a new repository (no need to add README/license if you already have them locally).
  2. Add the remote and push:

     ```bash
     git remote add origin https://github.com/YOUR_ORG_OR_USER/REPO_NAME.git
     git branch -M main
     git push -u origin main
     ```

Ensure the repo has this structure (already present if you cloned this bootstrap):

- `terraform/`
- `app/`
- `kubernetes/`
- `scripts/`
- `.github/workflows/`
- `docs/`

## 2. Sensitive files excluded

Confirm `.gitignore` excludes at least:

- `*.tfvars`, `*.tfvars.json`
- Service account keys: `*-key.json`, `*.pem`, `credentials.json`, etc.
- `.env` (keep `.env.example` if you use one)

Never commit Terraform variables files that contain secrets or the GCP service account key.

## 3. Branch protection (default branch)

On **Settings → General → Default branch**, set the default branch (e.g. `main`).

Then go to **Settings → Code and automation → Branches → Add branch protection rule** (or edit the rule for the default branch):

- **Branch name pattern**: `main` (or your default branch).
- **Require a pull request before merging**
  - Enable.
  - Require at least **1 approval** (or more if your org policy requires it).
- **Require status checks to pass before merging**
  - Enable.
  - **Require branches to be up to date** (recommended).
  - Add **required status checks** when they exist (e.g. from GitHub Actions):
    - After the CI/CD ticket, add the workflow job names that must pass (e.g. `terraform-validate`, `container-scan`, `deploy`).
    - For now you can leave the list empty; add checks once workflows are in place.
- **Do not allow bypassing the above settings** (if your plan allows it).
- **Restrict who can push to matching branches** (optional): limit to specific users/teams.
- Save the rule.

## 4. Required PR reviews

Handled in the branch protection rule above: “Require a pull request before merging” with at least 1 approval. Adjust the number of required reviewers if needed.

## 5. Required status checks

Also in the same branch protection rule: “Require status checks to pass before merging.” Once you have GitHub Actions workflows (CI/CD ticket), add their job names as required status checks so merges are blocked until those jobs pass.

## 6. Secret scanning

- **Public repositories**: Secret scanning is available for public repos; enable it if you want to satisfy the exercise requirement with a public repo.
- **Private repositories**: Requires **GitHub Advanced Security** (often included with GitHub Team/Enterprise).

To enable:

- Go to **Settings → Code security and analysis**.
- Under **Secret scanning**, click **Enable** (or **Enable for all repositories** at org level).

## 7. Dependabot alerts

- Go to **Settings → Code security and analysis**.
- Enable **Dependabot alerts** (and optionally **Dependabot security updates**).

## 8. Validation checkpoints (Flow 1)

- [ ] GitHub repository exists with structure: `terraform/`, `app/`, `kubernetes/`, `scripts/`, `.github/workflows/`, `docs/`.
- [ ] `.gitignore` excludes sensitive files (`.tfvars`, service account keys).
- [ ] Branch protection is enabled on the default branch.
- [ ] Required PR reviews are configured (e.g. 1 approval).
- [ ] Required status checks are configured (add specific checks once CI/CD workflows exist).
- [ ] Secret scanning is enabled (repo is public or GitHub Advanced Security is enabled).
- [ ] Dependabot alerts are enabled.
- [ ] Initial README documents the exercise overview.

## 9. Optional: GitHub CLI for branch protection

If you use `gh` and want to script branch protection (example for `main`):

```bash
# Require PR and 1 review, require status checks (no specific checks yet)
gh api repos/:owner/:repo/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"contexts":[]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_approval_count":1}' \
  -f restrictions=null
```

Replace `:owner/:repo` with your org/repo. Add `contexts` (workflow job names) once your CI/CD workflows are defined.
