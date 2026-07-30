# Independent regional failover

1. Apply the EU Central and EU West profiles independently, with different VPC CIDRs, RDS databases, artifact buckets, and intermediate KMS keys.
2. Create the EU West intermediate with its Terraform output key ID, but sign it during the approved ceremony with the single shared root from the designated security region. Publish the shared root and the EU West intermediate certificate only to the EU West artifact bucket.
3. Configure the same approved Google Workspace OIDC client in both regions if user enrollment must survive a regional outage. AWS IID uses regional AWS-internal SANs; it must be configured separately for each region.
4. Apply the global Route 53 failover environment with each regional ALB DNS name and hosted-zone ID. Use the regional CA names for normal enrollment and reserve the global name for tested client failover.
5. Test failure by withdrawing the primary ALB targets. Confirm Route 53 returns the secondary target and that a client already trusting the shared root can bootstrap and enroll against the second regional CA.

Do not assume JWK one-time tokens, ACME accounts, revocations, or PostgreSQL state replicate between regions. Keep those workflows region-affine or use a separately reviewed broker. A root certificate remains the trust anchor; clients must not pin one regional intermediate.
