# Lean / PoC threat model

## Assets and trust boundaries

| Asset | Required protection | Boundary |
|---|---|---|
| Root CA private key | AWS KMS asymmetric key; disabled except in an approved ceremony; CloudTrail alarm on every `Sign` | Security account/role; never the CA runtime |
| Intermediate CA private key | AWS KMS asymmetric key; `kms:Sign` only for runtime role | CA runtime account/role |
| CA certificates and config | Versioned private S3 artifact bucket; reviewable public files | Artifact publisher → runtime read-only path |
| Provisioner secrets | Secrets Manager/SSM or interactive operator credential; never Terraform state | Provisioner administrator |
| Issuance state | Encrypted EBS Badger data and tested backup | Single PoC host |
| Audit logs | Versioned S3 CloudTrail delivery and CloudWatch log group | Separate audit retention boundary |

## Key threats and required controls

| Threat | Control in this repository | Residual action before production |
|---|---|---|
| Runtime compromises root key | Root key policy lacks runtime principal; root disabled by default; root `Sign` alarm | Enforce separation with SCP and a distinct AWS account |
| Runtime issues arbitrary SAN | Authority allowlist plus per-provisioner rollout gate | Add provisioner-specific templates and negative e2e tests |
| CA private key leaks through IaC | Terraform creates KMS keys only; ceremony writes public `.crt` files | Review plans/state access and retain state audit evidence |
| Host SSH compromise | No SSH ingress, IMDSv2 required, EC2 role | Enforce SSM-only access and patch cadence in account baseline |
| Artifact tampering | Runtime S3 read-only; publisher scoped to `runtime/certs/*.crt` | Add signed artifact verification/SBOM before production |
| Host loss | Configuration and public certs are reconstructible; state volume requires backup | Test backup restore and document RTO/RPO |
| CA outage | Clients must renew early with jitter/backoff | Build PostgreSQL HA / second-region profile when required |

## Explicit non-goals for this profile

- High availability, OCSP, and multi-region recovery.
- General IAM-role enrollment broker.
- Organization/group authorization without a verified claims broker.
- Long-lived device certificates that need immediate revocation.

These are production work items, not settings to turn on in the Lean profile.
