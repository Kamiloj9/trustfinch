# Lean / PoC deployment runbook

1. Complete the identity matrix and threat model. Replace all `example.internal` values in the environment variables file.
2. Create a versioned, encrypted S3 state bucket outside this stack and use `backend.hcl` copied from the example. Use short-lived AWS credentials.
3. Run `make test`, then `terraform init -backend-config=backend.hcl`, `terraform fmt -check -recursive`, and a reviewed `terraform plan` from `environments/dev/eu-central-1`.
4. Apply with `root_key_enabled = false`. This creates a disabled root key, enabled intermediate key, runtime role, network, audit trail, and runtime artifact bucket.
5. In a separately reviewed, time-bound change, apply with `root_key_enabled = true`. Run the ceremony using a role listed in `root_ceremony_role_arns` and publish its reviewed public certificates.
6. Immediately apply with `root_key_enabled = false`. Verify a root `kms:Sign` CloudTrail event reaches the alarm path. Record the time and change ticket.
7. Let the EC2 systemd service fetch the runtime configuration and public certificates. Verify `https://<ca_fqdn>/health` and validate the root fingerprint through an independent trusted channel.
8. Add exactly one provisioner only after its identity matrix row and negative tests are approved. Do not begin with Google/GitLab/EC2/IAM broker simultaneously.

## Safety checks

- Never run the root ceremony as the EC2 runtime role.
- Never put a provisioner password, OIDC client secret, AWS access key, or a CA private key in `*.tfvars`, user data, logs, Git, or the artifact bucket.
- The default public `0.0.0.0/0` ingress value is a deliberate PoC convenience. Narrow it to VPN/NAT CIDRs for a private CA endpoint before production.
- `root_key_enabled=true` is an emergency-sensitive value. A plan that changes it must be reviewed as a ceremony change.
