# Changelog

All notable changes to FilePipe. Versions follow MAJOR.MINOR.PATCH.

## [Unreleased]

## [v1.0.0] - 2026-11-03
### Added
- CSV cleaning with rejects file and JSON logging
- Docker image (multi-stage, non-root)
- Terraform bootstrap: state bucket, ECR, GitHub OIDC role
- Terraform module for dev/test/prod
- Ansible deployment with nightly cron
- CloudWatch failure alarm with email alerts
- CI pipeline: lint, tests, image build and security scan
### Fixed
- Data folders created in the image for the non-root user
- Service user given a home folder for Docker credentials
- Trivy pinned to safe versions after a supply-chain incident