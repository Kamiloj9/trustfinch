# Provisioner rollout

The shipped `ca.json` has no provisioners. This is intentional: an online CA that starts with a broad bootstrap token is not a safe production baseline.

Add provisioners only after the corresponding row in [the identity matrix](../policies/identity-matrix.md) has approved values and negative tests. Use `step ca provisioner` rather than hand-editing an existing provisioner, then restart the service (or use remote management after its own administrative controls are approved).

Recommended order:

1. A tightly controlled administrative JWK or OIDC provisioner, with its secret outside Terraform state.
2. Google Workspace OIDC for verified users.
3. EC2 IID with explicit accounts, short instance age, `disableCustomSANs`, and no TOFU.
4. GitLab OIDC with exact issuer, audience, project-path, and protected-ref checks.
5. ACME after DNS/challenge ownership rules are tested.

Do not expose a JWK provisioner password in Git, Terraform variables, user data, CloudWatch logs, or a long-lived CI variable.
