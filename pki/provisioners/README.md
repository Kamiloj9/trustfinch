# Provisioner rollout

The shipped `ca.json` has no provisioners. This is intentional: an online CA that starts with a broad bootstrap token is not a safe production baseline.

Add provisioners only after the corresponding row in [the identity matrix](../policies/identity-matrix.md) has approved values and negative tests. The Terraform profiles can render the conservative Google Workspace and AWS IID provisioners from reviewed inputs. Google uses a Secrets Manager JSON value with a `client_secret` field; Terraform and the S3 artifact retain only a placeholder. Increment the production `runtime_release_id` after a provisioner change.

Recommended order:

1. A tightly controlled administrative JWK or OIDC provisioner, with its secret outside Terraform state.
2. Google Workspace OIDC for verified users; the included template emits only a verified e-mail client certificate.
3. EC2 IID with explicit accounts, short instance age, `disableCustomSANs`, and no TOFU. It can attest only the IID's private IP and AWS internal DNS name; use the broker for a custom workload DNS/SPIFFE identifier.
4. GitLab OIDC with exact issuer, audience, project-path, and protected-ref checks.
5. ACME after DNS/challenge ownership rules are tested.

Do not expose a JWK provisioner password in Git, Terraform variables, user data, CloudWatch logs, or a long-lived CI variable.
