terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "gitlab_terraform_deployment" {
  source = "../../modules/gitlab-terraform-oidc"

  name                     = "pki-test"
  oidc_provider_arn        = "arn:aws:iam::111122223333:oidc-provider/gitlab.com"
  oidc_provider_url        = "https://gitlab.com"
  audience                 = "sts.amazonaws.com"
  plan_subjects            = ["project_path:platform/pki:ref_type:branch:ref:main"]
  apply_subjects           = ["project_path:platform/pki:ref_type:tag:ref:deploy-test"]
  plan_additional_claims   = { project_id = ["12345"], ref_protected = ["true"] }
  apply_additional_claims  = { project_id = ["12345"], ref_protected = ["true"] }
  plan_policy_arns         = ["arn:aws:iam::111122223333:policy/pki-test-terraform-plan"]
  apply_policy_arns        = ["arn:aws:iam::111122223333:policy/pki-test-terraform-apply"]
  permissions_boundary_arn = "arn:aws:iam::111122223333:policy/pki-terraform-boundary"
}
