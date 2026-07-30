provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "self-hosted-pki"
      Environment = "prod"
      Region      = "eu-central-1"
    }
  }
}

locals {
  tags = {
    ManagedBy   = "Terraform"
    Project     = "self-hosted-pki"
    Environment = "prod"
    Region      = "eu-central-1"
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
  runtime_release_id              = var.runtime_release_id
  allowed_https_cidrs             = var.allowed_https_cidrs
  acm_certificate_arn             = var.acm_certificate_arn
  certificate_publisher_role_arns = var.certificate_publisher_role_arns
  tags                            = local.tags
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
  runtime_role_arn                = module.step_ca_ha.runtime_role_arn
  key_administrator_arns          = var.key_administrator_arns
  root_ceremony_role_arns         = var.root_ceremony_role_arns
  intermediate_ceremony_role_arns = var.root_ceremony_role_arns
  root_key_enabled                = var.root_key_enabled
  tags                            = local.tags
}

module "observability" {
  source = "../../../modules/observability"

  name          = var.name
  root_key_arn  = module.kms_ca.root_key_arn
  alarm_actions = var.alarm_actions
  tags          = local.tags
}

data "aws_iam_policy_document" "runtime_kms" {
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
}

resource "aws_iam_role_policy" "runtime_kms" {
  name   = "step-ca-kms"
  role   = module.step_ca_ha.runtime_role_name
  policy = data.aws_iam_policy_document.runtime_kms.json
}

locals {
  ca_json = templatefile("${path.module}/../../../pki/config/ca-ha.json.tftpl", {
    aws_region          = var.aws_region
    ca_fqdn             = var.ca_fqdn
    intermediate_key_id = module.kms_ca.intermediate_key_id
    internal_dns_suffix = var.internal_dns_suffix
    trust_domain        = var.trust_domain
  })

  compose_file = templatefile("${path.module}/../../../pki/config/step-ca-ha-compose.yml.tftpl", {
    aws_region           = var.aws_region
    cloudwatch_log_group = aws_cloudwatch_log_group.runtime.name
    database_endpoint    = module.postgres.endpoint
    database_port        = module.postgres.port
    database_name        = module.postgres.database_name
    database_username    = module.postgres.username
  })
}

resource "aws_s3_object" "ca_config" {
  bucket                 = module.step_ca_ha.artifact_bucket_name
  key                    = "runtime/step-ca/ca.json"
  content                = local.ca_json
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

resource "aws_route53_record" "ca" {
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
