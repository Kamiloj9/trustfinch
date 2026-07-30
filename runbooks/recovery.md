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
