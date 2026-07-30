# Production single-region HA deployment

This runbook applies to `environments/prod/eu-central-1`; it is not a shortcut for promoting the Lean profile.

1. Confirm that two private and two public CIDRs fit the selected VPC CIDR, that the ACM certificate exactly covers `ca_fqdn`, and that Route 53 ownership is known.
2. Complete the identity matrix and approve the PostgreSQL backup retention, RTO/RPO, and incident alarm targets.
3. Copy `terraform.tfvars.example` and `backend.hcl.example` outside Git. Use short-lived AWS credentials and a reviewed plan.
4. Apply with `root_key_enabled = false`. This creates the multi-AZ network, ALB, two-node ASG, RDS PostgreSQL Multi-AZ, audit trail, and restricted artifact bucket.
5. In a time-bounded ceremony change, enable the root, create the public root/intermediate certificates, publish them to the production artifact bucket, and disable the root again. Confirm the root-sign CloudTrail alarm.
6. Verify each ALB target becomes healthy, confirm the ALB/RDS CloudWatch alarms are present, and inspect `step-ca` logs for PostgreSQL `verify-full` connectivity. The base profile has no provisioner; install an approved, restricted provisioner before attempting issuance.
7. After that provisioner is deployed, simulate one node loss. Verify the ALB removes it, the ASG replaces it, and restricted issuance continues. Record the RDS backup/restore exercise separately before declaring the environment production ready.

The public ALB has a WAF rule that blocks a source IP after 500 requests over five minutes. WAF rate limiting is approximate, not a precise quota: tune `waf_rate_limit` only after measuring client-NAT fan-out and legitimate enrollment bursts. Its request sampling is disabled so enrollment material is not retained by WAF.

The runtime retrieves only the RDS-managed password secret and a public RDS CA bundle. It has no path to the root key, certificate-provisioner password, or Terraform state.

For every reviewed runtime configuration or public-certificate update, increment `runtime_release_id` in the same reviewed change. This creates a new launch template version and performs a 50%-healthy rolling refresh; do not upload a certificate release without that corresponding Terraform apply.
