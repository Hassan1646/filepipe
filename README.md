# FilePipe

A nightly batch job that cleans payment CSV files, built as a DevOps learning project.

Good rows are cleaned (ISO dates, 2dp amounts) and written to `*_clean.csv`. Bad rows go to `*_rejects.csv` with a reason. Logs are JSON, and an alarm emails the team if a run fails.

## Architecture

You → GitHub pull request → CI pipeline (lint, test, scan, build) → image in ECR → Ansible deploys to EC2 → cron runs it nightly → files in S3 → logs and alarm in CloudWatch. Terraform builds all the AWS parts for dev, test and prod.

## Run it locally

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
INPUT_DIR=sample-data OUTPUT_DIR=output python -m app.filepipe
```

Or with Docker: `mkdir -p output && docker compose up --build`

## Repo layout

| Folder | What's in it |
| --- | --- |
| `app/`, `tests/` | The Python app and its tests |
| `terraform/bootstrap` | Shared state bucket, ECR repo, GitHub OIDC role (run once) |
| `terraform/modules/filepipe` | Everything one environment needs |
| `terraform/envs/{dev,test,prod}` | One folder per environment |
| `ansible/` | Server setup and deployment |
| `k8s/` | Kubernetes CronJob for a local kind cluster |
| `jenkins/`, `Jenkinsfile`, `.gitlab-ci.yml`, `.github/workflows/` | GitHub Actions, plus Jenkins or GitLab CI |
| `docs/` | ADRs, runbook, change and incident templates |

## Ways of working

- Every change: Jira ticket → `feature/FP-<n>-<name>` branch → pull request → review → merge.
- `main` is protected. CI must pass before merging.
- Releases are tags (`v1.2.0`) on `main`. See `CHANGELOG.md`.
- Prod changes need an approved change request (`docs/change-request-template.md`).
- If the alarm fires, follow `docs/runbook.md`.