# GitLab CI Terraform deployment identity

The checked-in GitLab pipeline uses GitLab ID tokens and AWS STS web identity. It does not accept, create, or store long-lived AWS access keys. Run `make test` locally before merging; it validates the Terraform OIDC module in Docker without AWS credentials.

## One-time account setup

1. Register the GitLab issuer as an AWS IAM OIDC provider. For GitLab.com, use issuer `https://gitlab.com` and audience `sts.amazonaws.com`. A self-managed issuer and its OpenID discovery/JWKS endpoints must be publicly reachable by AWS STS.
2. In the account baseline, create three customer-managed IAM policies per PKI environment: a read-only Terraform plan policy, an environment-scoped Terraform apply policy, and a permission boundary. Do not attach `AdministratorAccess`; the apply policy must cover only the reviewed PKI resources and region.
3. Enable `gitlab_terraform_deployment` in the relevant `terraform.tfvars` from its example. Use the exact protected `main` branch subject for `plan_subjects` and a different exact protected deployment tag for `apply_subjects`. GitLab.com deployments should also pin `project_id` and `ref_protected = true`; self-managed GitLab supports the `sub` and `aud` conditions but not all GitLab.com-specific claim keys.
4. Apply this role configuration once using a human short-lived bootstrap credential. Record the two Terraform outputs for the plan and apply role ARNs.

## GitLab project setup

Protect the default branch and every deployment tag named in `apply_subjects`. Protect the production environments in GitLab and require the appropriate deployment approvals.

Create these **protected** CI/CD variables for each enabled environment:

| Variable | Value |
|---|---|
| `PKI_<ENV>_TERRAFORM_PLAN_ROLE_ARN` | Terraform `gitlab_terraform_plan_role_arn` output |
| `PKI_<ENV>_TERRAFORM_APPLY_ROLE_ARN` | Terraform `gitlab_terraform_apply_role_arn` output |
| `PKI_<ENV>_TERRAFORM_BACKEND_HCL` | A protected GitLab *file* variable containing the reviewed backend configuration |

Use the variable names already referenced by [`.gitlab-ci.yml`](../.gitlab-ci.yml): `DEV`, `PROD_EUC1`, and `PROD_EUW1`. The backend file contains state location configuration, never AWS credentials. Do not define `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or an AWS profile variable in GitLab.

The pipeline runs plans only from the default branch. Apply jobs appear only for tags and still require a manual GitLab action. The AWS trust policies independently enforce the exact branch/tag subject and audience, so an unauthorized tag cannot obtain a role session.

GitLab’s current AWS OIDC guidance covers the STS trust relationship, audience, and available claim conditions: [GitLab OIDC with AWS](https://docs.gitlab.com/ci/cloud_services/aws/) and [GitLab ID-token claims](https://docs.gitlab.com/ci/secrets/id_token_authentication/).
