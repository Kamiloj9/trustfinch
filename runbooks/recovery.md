# Recovery runbook

## Lean / PoC recovery objective

The Lean profile can restore the CA runtime and issuance state after a host failure. It is not HA: issuance is unavailable during restore. Agree RTO/RPO before using it beyond a PoC.

## Recover a lost host

1. Isolate the failed instance and preserve its forensic evidence. Do not reuse its EBS volume before the incident decision.
2. Restore the Badger state directory from a tested encrypted EBS backup to a replacement volume. The database contains issuance/revocation and one-time-token state.
3. Reapply the reviewed Terraform configuration. The runtime role, intermediate KMS key, S3 public certificates, and config are recreated/reused from infrastructure state; the private intermediate key remains in KMS.
4. Attach or restore the state at `/var/lib/step-ca`, start `pki-runtime.service`, and verify health and issuance using a restricted test provisioner.
5. Confirm the replacement runtime can sign only with the intermediate key; confirm the root key remains disabled.
6. Record measured RTO/RPO, certificate issuance evidence, and any unrecoverable state. Rotate provisioner credentials if compromise is suspected.

## Quarterly evidence

Run the procedure in a non-production account. Include an attempted out-of-policy SAN, a root-key access denial from the runtime role, and an alarm test for a controlled root signing ceremony.

## Production HA recovery

The production single-region profile uses RDS PostgreSQL Multi-AZ rather than a host-mounted Badger database. For a failed CA node, the Auto Scaling group replaces it and the ALB removes unhealthy targets; confirm a new target becomes healthy and can issue a restricted test certificate.

For database corruption or regional-service failure, use the approved RDS point-in-time restore procedure into an isolated recovery environment. Update the runtime database endpoint and its Secrets Manager ARN only through reviewed Terraform. Validate the restored CA's issuance, one-time-token behavior, and revocation data before routing production traffic. Never restore a database by copying its password or CA key into Terraform state.
