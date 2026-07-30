# Identity → certificate policy matrix

Replace every example value and obtain approval before creating provisioners. A provisioner is not a policy by itself: each row must map to an authority policy and, where needed, a certificate template that rejects unapproved claims or SANs.

| Principal | Authentication | Allowed identifier / SAN | EKU | Maximum TTL | Required negative test |
|---|---|---|---|---:|---|
| Google Workspace employee | OIDC, verified company domain | verified e-mail only; no caller-selected DNS SAN | clientAuth | 8h | foreign issuer, audience, unverified e-mail, foreign domain, custom SAN |
| GitLab protected CI | GitLab OIDC | `spiffe://example.internal/gitlab/<project>` or approved DNS name | clientAuth/serverAuth | 24h | wrong `aud`, project, ref protection, replayed token, custom SAN |
| EC2 workload | AWS Instance Identity Document | `ip-<id>.workload.example.internal` from approved account | clientAuth/serverAuth | 24h | foreign account, old IID, custom SAN, TOFU bypass |
| ACME workload | ACME challenge | DNS names under approved subdomain | serverAuth | 24h | unauthorized challenge, DNS outside allowed zone |
| Bootstrap device | one-time JWK token, then mTLS | device ID bound at bootstrap | clientAuth | 30d | reused token, different device ID, expired token |

## Approval record

Before enabling a row, record the policy change review, test evidence, issuer/client ID, exact audiences, allowed groups/projects/accounts, and renewal/revocation behavior in the change ticket. Do not add the provisioner until that record exists.
