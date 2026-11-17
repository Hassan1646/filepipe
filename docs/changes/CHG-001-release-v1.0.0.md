# Change request: CHG-001

| Field | Value |
| --- | --- |
| Title | Release FilePipe v1.0.0 to prod |
| Jira ticket | FP-<number> (change request), FP-8 (build test and prod) |
| Requested by | Hassan |
| Planned date and time | 2026-11-17 21:45, outside the 02:00 batch window |
| Risk | Low. First release; prod holds no live data yet; test run successful; rollback is a single command |
| Approved by | (change manager) |

## What is changing
Deploy FilePipe v1.0.0 to the prod server with Ansible: install Docker, create the
filepipe service user, write the env file and run script, and schedule the nightly 02:00 cron job.
Prod infrastructure (VPC, server, buckets, alarm) is already built with Terraform.

## Why
First production release, so the Payments Data team's nightly file is processed automatically.

## Test evidence
- Release pipeline: <link to the green v1.0.0 GitHub Actions run>
- Image filepipe:v1.0.0 in ECR, scanned (Trivy) with no critical or high findings
- Test environment, 2026-11-17 21:12, v1.0.0 run by hand on the sample file:
  - "file processed", good_rows 4, rejected_rows 4
  - "run finished", status success
  - Clean and rejects files present in filepipe-test-output bucket
- Playbook idempotent in test (second run changed=0)

## Implementation steps
1. From main: `ansible filepipe -i inventories/prod/hosts.ini -m ping`
2. `ansible-playbook site.yml -i inventories/prod/hosts.ini -e @inventories/prod/group_vars.yml`
3. Upload the sample file to the prod input bucket and run the job by hand
4. Check the output files and the /filepipe/prod logs

## How we'll know it worked
Clean and rejects files in the prod output bucket; "run finished" in /filepipe/prod;
alarm filepipe-prod-run-failed in OK state.

## Rollback plan
No earlier version exists in prod, so rollback means stopping the job:
1. `ssh ec2-user@<prod-ip> 'sudo crontab -u filepipe -r'` to remove the nightly schedule
2. Notify the service owner
If needed, `terraform destroy` in envs/prod removes the server entirely.

## Outcome (fill in afterwards)