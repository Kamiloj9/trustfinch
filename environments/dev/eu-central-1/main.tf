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
  tags                            = local.tags
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
  )

  ca_json = templatefile("${path.module}/../../../pki/config/ca.json.tftpl", {
    aws_region           = var.aws_region
    ca_fqdn              = var.ca_fqdn
    intermediate_key_id  = module.kms_ca.intermediate_key_id
    internal_dns_suffix  = var.internal_dns_suffix
    trust_domain         = var.trust_domain
    dns_allowlist_json   = jsonencode(concat(["*.${var.internal_dns_suffix}"], var.aws_iid_dns_allowlist))
    email_allowlist_json = jsonencode(var.google_oidc == null ? [] : ["@${var.google_oidc.workspace_domain}"])
    provisioners_json    = jsonencode(local.provisioners)
  })

  compose_file = templatefile("${path.module}/../../../pki/config/step-ca-compose.yml.tftpl", {
    aws_region           = var.aws_region
    cloudwatch_log_group = aws_cloudwatch_log_group.runtime.name
  })

  caddyfile = templatefile("${path.module}/../../../pki/config/Caddyfile.tftpl", {
    ca_fqdn = var.ca_fqdn
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

resource "aws_s3_object" "ca_config" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/step-ca/ca.json"
  content                = local.ca_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "google_oidc_template" {
  bucket                 = module.step_ca_ec2.artifact_bucket_name
  key                    = "runtime/templates/google-workspace-x509.tpl"
  content                = file("${path.module}/../../../pki/templates/google-workspace-x509.tpl")
  content_type           = "text/plain"
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
