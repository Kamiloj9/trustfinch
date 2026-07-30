# Production single-region HA profile

This profile runs two private `step-ca` nodes in an Auto Scaling group across two Availability Zones. An ALB terminates the public endpoint with a regional ACM certificate; node-to-node state is stored in RDS PostgreSQL Multi-AZ. The online intermediate remains in AWS KMS. Nodes fetch the AWS regional RDS trust bundle and use PostgreSQL `verify-full`, so the database connection is both encrypted and server-authenticated.

Unlike the Lean profile, this stack requires an ACM certificate, two AZs, explicit ingress CIDRs, and a reviewed recovery test. RDS creates and manages the database password in Secrets Manager; Terraform does not accept or write the password. The runtime role fetches that one secret at boot and passes it to `step-ca` through a root-only Compose environment file.

Run `terraform init -backend-config=backend.hcl`, review the plan, and follow the ceremony sequence in `../../../ceremony/README.md`. Root enablement remains false except for the time-bounded ceremony.

Increment `runtime_release_id` for every reviewed runtime configuration or public-certificate release. Terraform then performs an Auto Scaling rolling refresh while keeping at least half of the desired capacity healthy.
