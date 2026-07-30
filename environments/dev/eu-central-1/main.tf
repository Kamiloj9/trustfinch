provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "self-hosted-pki"
      Environment = "dev"
    }
  }
}

locals {
  tags = {
    ManagedBy   = "Terraform"
    Project     = "self-hosted-pki"
    Environment = "dev"
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

module "network" {
  source = "../../../modules/network"

  name               = var.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.tags
}

module "observability" {
  source = "../../../modules/observability"

  name          = var.name
  root_key_arn  = module.kms_ca.root_key_arn
  alarm_actions = var.alarm_actions
  tags          = local.tags
}

resource "aws_cloudwatch_log_group" "runtime" {
  name              = module.observability.runtime_log_group_name
  retention_in_days = 90
  tags              = local.tags
}

module "step_ca_ec2" {
  source = "../../../modules/step-ca-ec2"

  name                            = var.name
  vpc_id                          = module.network.vpc_id
  subnet_id                       = module.network.public_subnet_ids[0]
  cloudwatch_log_group_name       = aws_cloudwatch_log_group.runtime.name
  allowed_https_cidrs             = var.allowed_https_cidrs
  certificate_publisher_role_arns = var.certificate_publisher_role_arns
  google_oidc_client_secret_arn   = try(var.google_oidc.client_secret_arn, null)
  gitlab_broker_jwk_secret_arn    = try(var.gitlab_oidc.broker_jwk_secret_arn, null)
  tags                            = local.tags
}

module "backup" {
  source = "../../../modules/backup"

  name = var.name
  resource_arns = [
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/${module.step_ca_ec2.state_volume_id}",
  ]
  retention_days = var.backup_retention_days
  alarm_actions  = var.alarm_actions
  tags           = local.tags
}

module "gitlab_enrollment_replay" {
  count  = var.gitlab_oidc == null ? 0 : 1
  source = "../../../modules/gitlab-enrollment-replay"

  name              = var.name
  runtime_role_name = module.step_ca_ec2.runtime_role_name
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

module "kms_ca" {
  source = "../../../modules/kms-ca"

  name                            = var.name
  runtime_role_arn                = module.step_ca_ec2.runtime_role_arn
  key_administrator_arns          = var.key_administrator_arns
  root_ceremony_role_arns         = var.root_ceremony_role_arns
  intermediate_ceremony_role_arns = var.root_ceremony_role_arns
  root_key_enabled                = var.root_key_enabled
  tags                            = local.tags
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid       = "RuntimeReadsIntermediatePublicKey"
    effect    = "Allow"
    actions   = ["kms:GetPublicKey"]
    resources = [module.kms_ca.intermediate_key_arn]
  }

  statement {
    sid       = "RuntimeSignsWithIntermediateOnly"
    effect    = "Allow"
    actions   = ["kms:Sign"]
    resources = [module.kms_ca.intermediate_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:SigningAlgorithm"
      values   = ["ECDSA_SHA_256"]
    }
  }

  statement {
    sid       = "WriteRuntimeLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.runtime.arn}:*"]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "step-ca-kms-and-logs"
  role   = module.step_ca_ec2.runtime_role_name
  policy = data.aws_iam_policy_document.runtime.json
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

  ca_json = templatefile("${path.module}/../../../pki/config/ca.json.tftpl", {
    aws_region           = var.aws_region
    ca_fqdn              = var.ca_fqdn
    intermediate_key_id  = module.kms_ca.intermediate_key_id
    internal_dns_suffix  = var.internal_dns_suffix
    trust_domain         = var.trust_domain
    dns_allowlist_json   = jsonencode(concat(["*.${var.internal_dns_suffix}"], var.aws_iid_dns_allowlist, var.acme == null ? [] : var.acme.dns_allowlist))
    email_allowlist_json = jsonencode(var.google_oidc == null ? [] : ["@${var.google_oidc.workspace_domain}"])
    provisioners_json    = jsonencode(local.provisioners)
  })

  compose_file = templatefile("${path.module}/../../../pki/config/step-ca-compose.yml.tftpl", {
    aws_region            = var.aws_region
    cloudwatch_log_group  = aws_cloudwatch_log_group.runtime.name
    ca_fqdn               = var.ca_fqdn
    gitlab_broker_enabled = var.gitlab_oidc != null
    gitlab_broker_image   = try(var.gitlab_oidc.broker_image, "")
  })

  caddyfile = templatefile("${path.module}/../../../pki/config/Caddyfile.tftpl", {
    ca_fqdn               = var.ca_fqdn
    gitlab_broker_enabled = var.gitlab_oidc != null
  })
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

resource "aws_s3_object" "ca_config" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/step-ca/ca.json"
  content                = local.ca_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "step_ca_entrypoint" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/step-ca/step-ca-entrypoint.sh"
  content                = file("${path.module}/../../../pki/runtime/step-ca-entrypoint.sh")
  content_type           = "text/x-shellscript"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "step_ca_log_redactor" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/step-ca/redact-step-ca-logs.sh"
  content                = file("${path.module}/../../../pki/runtime/redact-step-ca-logs.sh")
  content_type           = "text/x-shellscript"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "google_oidc_template" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/templates/google-workspace-x509.tpl"
  content                = file("${path.module}/../../../pki/templates/google-workspace-x509.tpl")
  content_type           = "text/plain"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "gitlab_broker_config" {
  count = var.gitlab_oidc == null ? 0 : 1

  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/gitlab-broker/config.json"
  content                = local.gitlab_broker_config_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "compose" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/step-ca-compose.yml"
  content                = local.compose_file
  content_type           = "text/yaml"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "caddyfile" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/caddy/Caddyfile"
  content                = local.caddyfile
  content_type           = "text/plain"
  server_side_encryption = "AES256"
}

module "dns" {
  source = "../../../modules/dns-tls"

  hosted_zone_id = var.hosted_zone_id
  ca_fqdn        = var.ca_fqdn
  public_ip      = module.step_ca_ec2.public_ip
}
