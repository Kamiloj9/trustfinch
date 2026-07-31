<div align="center">

# Trustfinch

**Self-hosted PKI for teams that want simple, verifiable trust.**

Build a small trust foundation first. Keep every expansion deliberate.

[![CI](https://github.com/Kamiloj9/trustfinch/actions/workflows/ci.yml/badge.svg)](https://github.com/Kamiloj9/trustfinch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Kamiloj9/trustfinch?display_name=tag&include_prereleases&label=release)](https://github.com/Kamiloj9/trustfinch/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-3da639.svg)](LICENSE)

[Get started](#get-started) · [Milestones](MILESTONES.md) · [Deployment guide](runbooks/deployment.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

</div>

Trustfinch is an open-source AWS-backed PKI foundation built around `step-ca` and AWS KMS. It keeps CA private keys out of Terraform state, container images, and EC2 filesystems, while making every ceremony, policy change, and deployment boundary reviewable.

It is designed for short-lived workload certificates—not as a shortcut around PKI design. Start with the Lean profile, approve one narrow identity-to-certificate rule, and grow only after the evidence is there.

## Why Trustfinch?

| Key custody | Enrollment & policy | Operational evidence |
| --- | --- | --- |
| Root and intermediate CA keys stay in AWS KMS. The runtime may sign only with the intermediate. | Identity-to-SAN rules, allowlists, and negative tests keep issuance intentional. | Docker acceptance tests, public-history audit, SPDX SBOMs, checksums, and release evidence are built in. |
| Root use is explicit, ceremony-bound, and alarmed. | Google, GitLab, EC2 IID, ACME, and IAM enrollment are controlled rollout stages—not defaults. | Recovery, revocation, failover, log redaction, image verification, and artifact verification have runbooks and local checks. |

## Get started

First, validate the complete project locally. Docker Desktop and `rg` (ripgrep) are required; PKI, Terraform, and supply-chain workloads run in pinned containers.

```sh
git clone git@github.com:Kamiloj9/trustfinch.git
cd trustfinch
make test
make public-audit
```

For a first Lean deployment in `eu-central-1`, use the guided setup—not a copied example configuration:

```sh
scripts/trustfinch-setup.sh --help
```

The guide requires an existing hardened S3 Terraform backend and short-lived AWS credentials. It starts with the root disabled, pauses for the human root/intermediate ceremony, publishes reviewed **public** certificates only, then seals the root and verifies health and the fingerprint. It never creates the state backend or stores CA private keys.

Read the [threat model](runbooks/threat-model.md) and complete the [identity → certificate policy matrix](pki/policies/identity-matrix.md) before any deployment.

## Choose the right flight path

| Profile | What it is for | Before you rely on it |
| --- | --- | --- |
| **Lean · `dev/eu-central-1`** | A guided, single-instance foundation using Badger and one EC2 host. | Complete the ceremony, approve one provisioner, and record recovery evidence. It is not HA. |
| **Production HA · `prod/eu-central-1`** | Two private CA nodes behind an ALB with RDS PostgreSQL Multi-AZ. | Complete the [HA deployment runbook](runbooks/ha-deployment.md), node-loss test, and backup/restore evidence. |
| **Regional failover · EU Central + EU West** | Independent intermediates under one root, with Route 53 primary/secondary routing. | Complete the [multi-region failover runbook](runbooks/multi-region.md) and prove client enrollment through the secondary region. |

## What is included

- AWS Terraform modules for network boundaries, KMS-backed CA keys, hardened runtimes, Route 53, CloudTrail, CloudWatch, backup, and production HA.
- A controlled KMS root/intermediate ceremony that writes only public certificates outside KMS.
- Short-lived certificate issuance, bounded and jittered renewal, passive revocation, and tested restore/failover behavior.
- GitLab deployment identity through OIDC, optional GitLab enrollment, and an IAM enrollment broker—each kept separate from GitHub Actions deployment authority.
- Optional KMS-signed runtime artifacts plus Cosign-signed image digests with SPDX attestations.
- A public release workflow that publishes source, SBOM, checksums, test/audit output, and an evidence manifest. It never receives AWS credentials or Terraform apply access.

See [MILESTONES.md](MILESTONES.md) for what comes next and the evidence required to call each milestone complete.

## Project map

| Need | Start here |
| --- | --- |
| First Lean deployment | [guided setup](scripts/trustfinch-setup.sh) · [deployment runbook](runbooks/deployment.md) |
| Certificate policy | [identity matrix](pki/policies/identity-matrix.md) · [provisioner notes](pki/provisioners/README.md) |
| Recovery and revocation | [recovery](runbooks/recovery.md) · [revocation](runbooks/revocation.md) |
| Runtime and image releases | [artifact signing](runbooks/runtime-artifact-signing.md) · [image supply chain](runbooks/container-image-supply-chain.md) |
| Public project operations | [release publication](runbooks/github-publication.md) · [releases](https://github.com/Kamiloj9/trustfinch/releases) |

## Safety boundaries

- Never put a CA private key, provisioner secret, AWS access key, or static credential in Git, Terraform variables, logs, or runtime artifacts.
- Never enable the root key for an ordinary apply. It is enabled only for a reviewed, time-bounded ceremony and disabled immediately afterward.
- Do not copy example domains or permissive policy values into a real deployment.
- GitHub Actions validates and releases source evidence only. GitLab OIDC remains the optional deployment integration.

## Open source

Trustfinch is licensed under [Apache-2.0](LICENSE). Please read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) before participating. For security reports, follow [SECURITY.md](SECURITY.md)—please do not open a public issue for a suspected vulnerability.
