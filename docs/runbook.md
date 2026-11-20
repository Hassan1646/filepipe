# FilePipe runbook

**Service:** nightly payment CSV cleaner · **Runs:** 02:00 daily · **Owner:** Platform team

## How it works
Cron on the EC2 server runs `/usr/local/bin/run-filepipe.sh`, which pulls the Docker image from ECR and processes every `.csv` in `s3://<input-bucket>/incoming/`. Clean files go to `s3://<output-bucket>/processed/`. Logs go to CloudWatch log group `/filepipe/<env>`.

## Alarm: `filepipe-<env>-run-failed`
1. Open CloudWatch → Log groups → `/filepipe/<env>` and find the `ERROR` lines.
2. Check the `reason` field:
   - `no input files found` → ask the Payments Data team whether a file was sent.
   - `file is missing columns` → the supplier changed the file format. Do not edit the file.
     Quarantine it **from your own machine** (not the server: the server's role can't write to the input bucket):
     `aws s3 mv s3://<input-bucket>/incoming/<file> s3://<input-bucket>/quarantine/<file>`
     Then tell the service owner, and re-run the job by hand to check the other files.
   - Anything else → see "Run it by hand" below and raise an incident.
3. Record what you found in the incident ticket.

## Run it by hand
```bash
ssh -i ~/.ssh/filepipe ec2-user@<server-ip>
ssh-agent -k
```

## Deploy a new version
1. Merge to `main`, then tag: `git tag v1.1.0 && git push origin v1.1.0` (the pipeline pushes the image).
2. Change `filepipe_image` in the environment's Ansible vars to the new tag.
3. Run `ansible-playbook site.yml -e @inventories/<env>/group_vars.yml`.
4. For prod: only with an approved change ticket.

## Roll back
Set `filepipe_image` back to the previous tag and re-run the playbook. Images are immutable, so the old tag is exactly what ran before.