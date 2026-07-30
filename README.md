# Self-hosted PKI on AWS

This repository implements a secure self-hosted PKI foundation from the project plan. It runs [step-ca](https://smallstep.com/docs/step-ca/) with an AWS KMS-backed intermediate CA key in AWS; no CA private key is stored in Terraform state, a container image, or the EC2 filesystem.

The Lean profile does not claim production HA or multi-region recovery. The production HA profile still requires the decisions recorded in the threat model, an approved provisioner configuration, and disaster-recovery exercises before use.

## What is included

- Terraform modules for a VPC, KMS CA keys, a hardened EC2 runtime, optional Route 53 DNS, CloudTrail audit storage, CloudWatch root-key-use alarm, and runtime configuration artifacts.
- A KMS ceremony that creates only public root and intermediate certificates; KMS retains the private keys.
- A least-privilege runtime role: `kms:Sign` is limited to the intermediate key, while the root key is never granted to the runtime role.
- A pinned `step-ca` runtime and Caddy reverse proxy configuration.
- A disposable Docker integration test that issues an allowed certificate and rejects an out-of-policy SAN. The test CA uses on-disk keys in a removed Docker volume; it is never an AWS/KMS simulation.
- A production single-region profile with two private CA nodes, ALB, RDS PostgreSQL Multi-AZ, AWS-managed database credentials, and verified RDS TLS. Its Docker test uses the same PostgreSQL backend locally.
- An independent EU West HA profile with its own intermediate, state, and database, plus a global Route 53 primary/secondary alias environment. The regional profiles never create a second root.
- A reusable workload renewal helper with bounded retry, jittered scheduling, chain verification, and atomic certificate replacement.
- A passive-revocation runbook and local acceptance check proving revocation blocks future renewal within the short certificate lifetime.
- A tested runtime log boundary that redacts one-time enrollment tokens before logs reach CloudWatch.
- CloudWatch metrics and alarms for issuance by provisioner, CA errors/signing latency, root use, intermediate KMS failures and volume, HA target health, RDS capacity, and runtime disk use.
- GitLab CI deployment roles that exchange a GitLab ID token for a one-hour AWS STS session, with distinct branch-plan and deployment-tag apply roles.
- Acceptance checks that run with Docker on a developer machine: `make test`.

## Start here

1. Read [the threat model](runbooks/threat-model.md) and fill in the identity-to-SAN matrix in [pki/policies/identity-matrix.md](pki/policies/identity-matrix.md). Do not deploy with the example domain values.
2. Copy the relevant example variables file in `environments/`, replace placeholders, and run an AWS plan using short-lived credentials.
3. Apply with `root_key_enabled = true` only during the controlled ceremony. Run [ceremony/create-hierarchy.sh](ceremony/create-hierarchy.sh), publish the resulting **public** certificates, then immediately apply with `root_key_enabled = false`.
4. Follow [the recovery runbook](runbooks/recovery.md) and capture evidence of its test before treating the deployment as production-ready.

## Local validation

Docker Desktop is the only prerequisite.

```sh
make test
```

This runs Terraform formatting and validation in a pinned Terraform container, then starts a short-lived local CA in Docker. The local CA's keys exist only in the `docker compose` test volume and are deleted by the test cleanup. AWS credentials are not read or needed.

## Deployment boundaries

- `environments/dev/eu-central-1` is intentionally a PoC. It uses Badger and one EC2 instance; it is not valid for an HA deployment. Use `environments/prod/eu-central-1` only after completing its deployment and recovery runbook.
- Root-key enable/disable is an explicit input so an ordinary apply cannot silently make the root usable.
- Terraform does not generate CA private keys and no secret input is accepted for the CA key.
- Google, GitLab, EC2 IID, ACME, IAM-broker, HA, and multi-region provisioners are rollout stages, not values to copy into a permissive initial CA config. Add each only with its negative tests and an approved identity-to-SAN rule.

See [runbooks/deployment.md](runbooks/deployment.md) for the exact rollout order.
For recurring GitLab deployment access, use [the GitLab Terraform OIDC runbook](runbooks/gitlab-terraform-oidc.md); it deliberately has no static AWS-key fallback.
