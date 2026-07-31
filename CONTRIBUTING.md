# Contributing to Trustfinch

Thanks for helping improve Trustfinch. Security and operational correctness take priority over feature velocity.

## Before opening a pull request

1. Read the threat model and the relevant runbook.
2. Keep CA private keys, long-lived cloud credentials, Terraform state, real certificates, and production identifiers out of Git.
3. Run `make test` locally with Docker Desktop. Add a negative test whenever a policy or enrollment boundary changes.
4. Keep Terraform changes narrowly scoped and explain any change that can enable a root key, provisioner, or production network path.

## Pull requests

Use focused commits and describe the security impact, rollout path, and recovery implications. At least one maintainer review is required for PKI policy, ceremony, runtime, Terraform, or CI changes. Do not merge a release or deployment change without a successful local review of the generated plan and evidence.

By contributing, you agree that your contributions are licensed under Apache-2.0.
