# Provisioner rollout

The shipped `ca.json` has no provisioners. This is intentional: an online CA that starts with a broad bootstrap token is not a safe production baseline.

Add provisioners only after the corresponding row in [the identity matrix](../policies/identity-matrix.md) has approved values and negative tests. The Terraform profiles can render the conservative Google Workspace and AWS IID provisioners from reviewed inputs. Google uses a Secrets Manager JSON value with a `client_secret` field; Terraform and the S3 artifact retain only a placeholder. Increment the production `runtime_release_id` after a provisioner change.

Recommended order:

1. A tightly controlled administrative JWK or OIDC provisioner, with its secret outside Terraform state.
2. Google Workspace OIDC for verified users; the included template emits only a verified e-mail client certificate.
3. EC2 IID with explicit accounts, short instance age, `disableCustomSANs`, and no TOFU. It can attest only the IID's private IP and AWS internal DNS name; use the broker for a custom workload DNS/SPIFFE identifier.
4. GitLab CI ID tokens through the included enrollment broker. Native `step-ca` OIDC validates issuer and audience, but GitLab CI tokens use `jti` rather than the OIDC `nonce` that `step-ca` records for replay prevention. The broker validates the signed GitLab token, atomically consumes its `jti` in a regional DynamoDB table, and submits a fresh CSR-bound one-time JWK token to `step-ca`.
5. ACME after DNS/challenge ownership rules are tested.

Do not expose a JWK provisioner password in Git, Terraform variables, user data, CloudWatch logs, or a long-lived CI variable.

## GitLab CI enrollment broker

Set the optional `gitlab_oidc` object in the regional profile only after reviewing an explicit identity mapping for every protected branch or tag. Each mapping binds all of the following signed GitLab claims: exact issuer, `aud`, `project_id`, `project_path`, `ref_type`, `ref`, and `ref_protected=true`. It emits only the configured subject and SPIFFE URI SAN; a CSR with any other SAN is rejected before it reaches the CA.

The GitLab job must request an ID token with that exact audience, for example:

```yaml
issue-workload-certificate:
  id_tokens:
    PKI_ID_TOKEN:
      aud: https://ca.example.internal/gitlab/platform-pki
  script:
    - ./request-approved-gitlab-certificate "$PKI_ID_TOKEN"
```

`request-approved-gitlab-certificate` must send the token only in an `Authorization: Bearer` header and send a CSR whose common name and sole URI SAN exactly match the reviewed mapping to `POST /1.0/enroll/gitlab`. Never print the token, CSR response headers, or private key in CI logs. The broker returns the normal `step-ca` signing response and does not allow renewal.

The private P-256 JWK belongs in the referenced Secrets Manager secret as a raw JWK JSON value. Terraform stores only its public JWK in the `step-ca` provisioner. Build `broker/Dockerfile`, publish it to the target region's registry, then copy the immutable image digest into `gitlab_oidc.broker_image`. The runtime instance profile can read only that secret and the broker can conditionally claim, then (only if the downstream CA call fails) delete, its own token-ID record in the regional replay table.

Use a distinct broker JWK and audience in each region. This prevents a token minted for EU Central from being replayed against EU West; Route 53 endpoint failover does not make a regional GitLab enrollment token portable.

## AWS IAM SigV4 enrollment broker

Set the optional `iam_sigv4` object only for a reviewed workload role. Terraform creates an API Gateway HTTP API with a single `POST /1.0/enroll/iam` route using `AWS_IAM`; callers must SigV4-sign the request and have the exact emitted `execute-api:Invoke` policy. API Gateway validates the signature before the Lambda broker runs.

The Lambda accepts only the authenticated temporary `assumed-role` ARN exposed by API Gateway, normalizes it to the configured IAM role ARN, and rejects IAM users, federated principals, unreviewed roles, malformed requests, and every CSR except the role's exact common name and SPIFFE URI SAN. It turns that approved request into a two-minute CSR-bound JWK token for `step-ca`; the private P-256 JWK exists only in the referenced Secrets Manager secret.

Build `broker/iam-lambda.Dockerfile` for `linux/arm64` with provenance disabled, publish it to the region's ECR registry, and configure the immutable digest. The Lambda has a hard concurrency limit, can read only its own public configuration object and signing-key secret, and cannot sign with the CA KMS key. Keep a distinct JWK per region. Leave `ca_tls_root_certificate_pem` empty when the CA endpoint has a public Web-PKI certificate; otherwise supply only the public TLS trust root needed for Lambda-to-CA verification.
