# Recovery runbook

## Lean / PoC recovery objective

The Lean profile can restore the CA runtime and issuance state after a host failure. It is not HA: issuance is unavailable during restore. Agree RTO/RPO before using it beyond a PoC.

`make test-recovery` is the Docker-only acceptance exercise. It creates a disposable CA, revokes a certificate, snapshots the named state volume, destroys the original volume, restores the snapshot into a clean replacement volume, and proves both that the root fingerprint is unchanged and that the pre-backup revocation is still enforced. It is evidence for the state-recovery mechanics, not a substitute for an AWS Backup restore rehearsal or a measured production RTO/RPO.

## Recover a lost host

1. Isolate the failed instance and preserve its forensic evidence. Do not reuse its EBS volume before the incident decision.
2. In AWS Backup, locate a successful recovery point in the Terraform output `ca_state_backup_vault`. Restore the exact encrypted `step-ca-state` EBS volume into the same AZ as an isolated helper instance. Attach it as a secondary volume and mount it read-only at `/mnt/pki-recovery`; never boot the restored root disk directly. The volume contains issuance, revocation, and one-time-token state.
3. Reapply the reviewed Terraform configuration to create a replacement runtime. The runtime role, intermediate KMS key, S3 public certificates, and config are recreated/reused from infrastructure state; the private intermediate key remains in KMS.
4. Before serving traffic, stop `pki-runtime.service` on the replacement host. Copy only `/mnt/pki-recovery/var/lib/step-ca` to `/var/lib/step-ca` while preserving numeric ownership, then unmount the recovery volume. Do not replace the replacement host's rendered configuration, systemd unit, or IAM identity with files from the backup.
5. Start `pki-runtime.service`, verify health and restricted issuance, then retire the isolated helper instance and its restored volume according to the incident record.
6. Confirm the replacement runtime can sign only with the intermediate key; confirm the root key remains disabled.
7. Record measured RTO/RPO, certificate issuance evidence, and any unrecoverable state. Rotate provisioner credentials if compromise is suspected.

## Quarterly evidence

Run the procedure in a non-production account at least quarterly. Record the recovery-point ID, elapsed RTO, data age/RPO, restored-volume encryption, successful restricted issuance, an attempted out-of-policy SAN, a root-key access denial from the runtime role, and an alarm test for a controlled root signing ceremony.

## Production HA recovery

The production single-region profile uses RDS PostgreSQL Multi-AZ rather than a host-mounted Badger database. For a failed CA node, the Auto Scaling group replaces it and the ALB removes unhealthy targets; confirm a new target becomes healthy and can issue a restricted test certificate.

For database corruption or regional-service failure, use the approved RDS point-in-time restore procedure into an isolated recovery environment. Update the runtime database endpoint and its Secrets Manager ARN only through reviewed Terraform. Validate the restored CA's issuance, one-time-token behavior, and revocation data before routing production traffic. Never restore a database by copying its password or CA key into Terraform state.
