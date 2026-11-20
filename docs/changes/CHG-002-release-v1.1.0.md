# Change request: CHG-002

| Field | Value |
| --- | --- |
| Title | Release FilePipe v1.1.0 to prod |
| Jira ticket | FP-25 |
| Requested by | Hassan |
| Planned date and time | 2026-11-20 22:55, outside the 02:00 batch window |
| Risk | Low. Small change: REVERSED added as a valid status; tested; rollback to v1.0.0 is one playbook run |
| Approved by | (change manager) |

## What is changing
Prod image changes from filepipe:v1.0.0 to filepipe:v1.1.0 (REVERSED is now a valid payment status).

## Why
Payments can now be reversed; those rows should be processed, not rejected.

## Test evidence
- PR: <link>; pytest 10 passed (new test for REVERSED); flake8 clean
- GitHub Actions and GitLab pipelines green, including the Trivy image scan
- Release pipeline for tag v1.1.0: <link>; image filepipe:v1.1.0 in ECR
- Current prod version before the change: filepipe:v1.0.0

## Implementation steps
1. Merge this PR (prod group_vars → v1.1.0)
2. From main: `ansible-playbook site.yml -i inventories/prod/hosts.ini -e @inventories/prod/group_vars.yml`
3. Check the version: `grep -o "filepipe:v[0-9.]*" /usr/local/bin/run-filepipe.sh` on the server
4. Run the job by hand with the sample file; check output and logs

## How we'll know it worked
Server shows filepipe:v1.1.0; prod run ends "run finished", success; alarm in OK.

## Rollback plan
1. Set filepipe_image back to filepipe:v1.0.0 in inventories/prod/group_vars.yml
2. Re-run the playbook against prod
3. Check the server shows filepipe:v1.0.0 and a run succeeds
4. Record the rollback in this change and in Jira
Images are immutable, so v1.0.0 is exactly the version that ran before.

## Outcome (fill in afterwards)
## Outcome (fill in afterwards)
**Rolled back.**
- 22:44 Released v1.1.0 (playbook changed=1, failed=0); server showed filepipe:v1.1.0
- 22:45 Verification run: "run finished", success
- ~22:46 Service owner reported unexpected REVERSED payments in the finance report
- 22:46 Rolled back using the approved rollback plan: playbook with filepipe_image=v1.0.0 (changed=1, failed=0)
- 22:46 Server shows filepipe:v1.0.0; verification run "run finished", success
- Follow-up: v1.1.0 to be reviewed with the finance team before re-release (new Jira ticket)
- main updated to match prod in the rollback PR