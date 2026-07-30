provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    ManagedBy   = "Terraform"
    Project     = "self-hosted-pki"
    Environment = "prod"
    Region      = "eu-west-1"
  }
}

module "network" {
  source = "../../../modules/network-ha"

  name               = var.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.tags
}

resource "aws_cloudwatch_log_group" "runtime" {
  name              = "/pki/${var.name}/runtime"
  retention_in_days = 365
  tags              = local.tags
}

module "step_ca_ha" {
  source = "../../../modules/step-ca-ha"

  name                            = var.name
  aws_region                      = var.aws_region
  vpc_id                          = module.network.vpc_id
  private_subnet_ids              = module.network.private_subnet_ids
  public_subnet_ids               = module.network.public_subnet_ids
  cloudwatch_log_group_arn        = aws_cloudwatch_log_group.runtime.arn
  cloudwatch_log_group_name       = aws_cloudwatch_log_group.runtime.name
  database_secret_arn             = module.postgres.master_secret_arn
  google_oidc_client_secret_arn   = try(var.google_oidc.client_secret_arn, null)
  gitlab_broker_jwk_secret_arn    = try(var.gitlab_oidc.broker_jwk_secret_arn, null)
  gitlab_broker_enabled           = var.gitlab_oidc != null
  runtime_release_id              = var.runtime_release_id
  allowed_https_cidrs             = var.allowed_https_cidrs
  acm_certificate_arn             = var.acm_certificate_arn
  certificate_publisher_role_arns = var.certificate_publisher_role_arns
  tags                            = local.tags
}

module "gitlab_enrollment_replay" {
  count  = var.gitlab_oidc == null ? 0 : 1
  source = "../../../modules/gitlab-enrollment-replay"

  name              = var.name
  runtime_role_name = module.step_ca_ha.runtime_role_name
  tags              = local.tags
}

module "iam_enrollment_gateway" {
  count  = var.iam_sigv4 == null ? 0 : 1
  source = "../../../modules/iam-enrollment-gateway"

  name               = var.name
  lambda_image_uri   = try(var.iam_sigv4.lambda_image, "")
  jwk_secret_arn     = try(var.iam_sigv4.broker_jwk_secret_arn, "")
  broker_config_json = local.iam_broker_config_json
  tags               = local.tags
}

module "postgres" {
  source = "../../../modules/postgres"

  name                     = var.name
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_subnet_ids
  client_security_group_id = module.step_ca_ha.node_security_group_id
  instance_class           = var.postgres_instance_class
  tags                     = local.tags
}

module "kms_ca" {
  source = "../../../modules/kms-ca"

  name                            = var.name
  create_root_key                 = false
  runtime_role_arn                = module.step_ca_ha.runtime_role_arn
  key_administrator_arns          = var.key_administrator_arns
  root_ceremony_role_arns         = []
  intermediate_ceremony_role_arns = var.intermediate_ceremony_role_arns
  tags                            = local.tags
}

module "observability" {
  source = "../../../modules/observability"

  name                   = var.name
  root_key_arn           = null
  intermediate_key_arn   = module.kms_ca.intermediate_key_arn
  runtime_log_group_name = aws_cloudwatch_log_group.runtime.name
  alarm_actions          = var.alarm_actions
  tags                   = local.tags
}

data "aws_iam_policy_document" "runtime_kms" {
  statement {
    effect    = "Allow"
    actions   = ["kms:GetPublicKey"]
    resources = [module.kms_ca.intermediate_key_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Sign"]
    resources = [module.kms_ca.intermediate_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:SigningAlgorithm"
      values   = ["ECDSA_SHA_256"]
    }
  }
}

resource "aws_iam_role_policy" "runtime_kms" {
  name   = "step-ca-kms"
  role   = module.step_ca_ha.runtime_role_name
  policy = data.aws_iam_policy_document.runtime_kms.json
}

locals {
  provisioners = concat(
    var.google_oidc == null ? [] : [{
      type                  = "OIDC"
      name                  = "Google Workspace"
      clientID              = var.google_oidc.client_id
      clientSecret          = "$${GOOGLE_OIDC_CLIENT_SECRET}"
      configurationEndpoint = "https://accounts.google.com/.well-known/openid-configuration"
      domains               = [var.google_oidc.workspace_domain]
      scopes                = ["openid", "email"]
      listenAddress         = ":10000"
      claims = {
        maxTLSCertDuration     = "8h"
        defaultTLSCertDuration = "8h"
        disableRenewal         = true
      }
      options = {
        x509 = {
          templateFile = "/home/step/templates/google-workspace-x509.tpl"
        }
      }
    }],
    length(var.aws_iid_accounts) == 0 ? [] : [{
      type                   = "AWS"
      name                   = "AWS IID"
      accounts               = var.aws_iid_accounts
      disableCustomSANs      = true
      disableTrustOnFirstUse = true
      instanceAge            = var.aws_iid_instance_age
      claims = {
        maxTLSCertDuration     = "24h"
        defaultTLSCertDuration = "24h"
      }
    }],
    var.acme == null ? [] : [{
      type = "ACME"
      name = "ACME"
      claims = {
        maxTLSCertDuration     = "24h"
        defaultTLSCertDuration = "24h"
      }
    }],
    var.gitlab_oidc == null ? [] : [{
      type = "JWK"
      name = "GitLab Enrollment Broker"
      key  = var.gitlab_oidc.broker_jwk_public
      claims = {
        maxTLSCertDuration     = "1h"
        defaultTLSCertDuration = "1h"
        disableRenewal         = true
      }
    }],
    var.iam_sigv4 == null ? [] : [{
      type = "JWK"
      name = "IAM Enrollment Broker"
      key  = var.iam_sigv4.broker_jwk_public
      claims = {
        maxTLSCertDuration     = "1h"
        defaultTLSCertDuration = "1h"
        disableRenewal         = true
      }
    }],
  )

  gitlab_broker_config_json = var.gitlab_oidc == null ? null : jsonencode({
    issuer                    = var.gitlab_oidc.issuer
    discovery_url             = "${var.gitlab_oidc.issuer}/.well-known/openid-configuration"
    replay_table_name         = module.gitlab_enrollment_replay[0].table_name
    ca_url                    = "https://${var.ca_fqdn}:9000"
    ca_server_name            = var.ca_fqdn
    ca_sign_audience          = "https://${var.ca_fqdn}/1.0/sign#GitLab%20Enrollment%20Broker:${var.gitlab_oidc.broker_jwk_public.kid}"
    broker_provisioner_name   = "GitLab Enrollment Broker"
    max_gitlab_token_lifetime = "1h"
    identities                = var.gitlab_oidc.identities
  })

  iam_broker_config_json = var.iam_sigv4 == null ? null : jsonencode(merge({
    ca_url                  = "https://${var.ca_fqdn}"
    ca_server_name          = var.ca_fqdn
    ca_sign_audience        = "https://${var.ca_fqdn}/1.0/sign#IAM%20Enrollment%20Broker:${var.iam_sigv4.broker_jwk_public.kid}"
    broker_provisioner_name = "IAM Enrollment Broker"
    identities              = var.iam_sigv4.identities
    }, var.iam_sigv4.ca_tls_root_certificate_pem == "" ? {} : {
    ca_root_certificate_pem = var.iam_sigv4.ca_tls_root_certificate_pem
  }))

  ca_json = templatefile("${path.module}/../../../pki/config/ca-ha.json.tftpl", {
    aws_region           = var.aws_region
    ca_fqdn              = var.ca_fqdn
    intermediate_key_id  = module.kms_ca.intermediate_key_id
    internal_dns_suffix  = var.internal_dns_suffix
    trust_domain         = var.trust_domain
    dns_allowlist_json   = jsonencode(concat(["*.${var.internal_dns_suffix}"], var.aws_iid_dns_allowlist, var.acme == null ? [] : var.acme.dns_allowlist))
    email_allowlist_json = jsonencode(var.google_oidc == null ? [] : ["@${var.google_oidc.workspace_domain}"])
    provisioners_json    = jsonencode(local.provisioners)
  })

  compose_file = templatefile("${path.module}/../../../pki/config/step-ca-ha-compose.yml.tftpl", {
    aws_region            = var.aws_region
    cloudwatch_log_group  = aws_cloudwatch_log_group.runtime.name
    ca_fqdn               = var.ca_fqdn
    gitlab_broker_enabled = var.gitlab_oidc != null
    gitlab_broker_image   = try(var.gitlab_oidc.broker_image, "")
    database_endpoint     = module.postgres.endpoint
    database_port         = module.postgres.port
    database_name         = module.postgres.database_name
    database_username     = module.postgres.username
  })
}

resource "aws_s3_object" "ca_config" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/step-ca/ca.json"
  content                = local.ca_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "step_ca_entrypoint" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/step-ca/step-ca-entrypoint.sh"
  content                = file("${path.module}/../../../pki/runtime/step-ca-entrypoint.sh")
  content_type           = "text/x-shellscript"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "step_ca_log_redactor" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/step-ca/redact-step-ca-logs.sh"
  content                = file("${path.module}/../../../pki/runtime/redact-step-ca-logs.sh")
  content_type           = "text/x-shellscript"
  server_side_encryption = "AES256"
}

resource "terraform_data" "aws_iid_policy_guard" {
  input = var.aws_iid_accounts

  lifecycle {
    precondition {
      condition     = length(var.aws_iid_accounts) == 0 || length(var.aws_iid_dns_allowlist) > 0
      error_message = "aws_iid_dns_allowlist must include the approved AWS internal DNS pattern when AWS IID is enabled."
    }
  }
}

resource "terraform_data" "gitlab_oidc_policy_guard" {
  input = var.gitlab_oidc

  lifecycle {
    precondition {
      condition     = var.gitlab_oidc == null || length(distinct([for identity in var.gitlab_oidc.identities : join("|", [identity.project_id, identity.audience, identity.ref_type, identity.ref])])) == length(var.gitlab_oidc.identities)
      error_message = "Every GitLab enrollment identity must have a unique project ID, audience, ref type, and ref mapping."
    }
  }
}

resource "aws_s3_object" "google_oidc_template" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/templates/google-workspace-x509.tpl"
  content                = file("${path.module}/../../../pki/templates/google-workspace-x509.tpl")
  content_type           = "text/plain"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "gitlab_broker_config" {
  count = var.gitlab_oidc == null ? 0 : 1

  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/gitlab-broker/config.json"
  content                = local.gitlab_broker_config_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "compose" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/step-ca-ha-compose.yml"
  content                = local.compose_file
  content_type           = "text/yaml"
  server_side_encryption = "AES256"
}

resource "aws_route53_record" "regional_ca" {
  count = var.hosted_zone_id == null ? 0 : 1

  zone_id = var.hosted_zone_id
  name    = var.ca_fqdn
  type    = "A"

  alias {
    name                   = module.step_ca_ha.load_balancer_dns_name
    zone_id                = module.step_ca_ha.load_balancer_zone_id
    evaluate_target_health = true
  }
}
