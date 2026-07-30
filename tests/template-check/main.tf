terraform {
  required_version = ">= 1.13.0, < 2.0.0"
}

locals {
  ca_config = jsondecode(templatefile("${path.module}/../../pki/config/ca.json.tftpl", {
    aws_region           = "eu-central-1"
    ca_fqdn              = "ca.test.example.internal"
    intermediate_key_id  = "00000000-0000-0000-0000-000000000000"
    internal_dns_suffix  = "test.example.internal"
    trust_domain         = "test.example.internal"
    dns_allowlist_json   = jsonencode(["*.test.example.internal"])
    email_allowlist_json = jsonencode([])
    provisioners_json    = jsonencode([])
  }))

  runtime_compose = templatefile("${path.module}/../../pki/config/step-ca-compose.yml.tftpl", {
    aws_region            = "eu-central-1"
    cloudwatch_log_group  = "/pki/test/runtime"
    ca_fqdn               = "ca.test.example.internal"
    gitlab_broker_enabled = false
    gitlab_broker_image   = ""
  })

  caddyfile = templatefile("${path.module}/../../pki/config/Caddyfile.tftpl", {
    ca_fqdn = "ca.test.example.internal"
  })

  ca_ha_config = jsondecode(templatefile("${path.module}/../../pki/config/ca-ha.json.tftpl", {
    aws_region           = "eu-central-1"
    ca_fqdn              = "ca.test.example.internal"
    intermediate_key_id  = "00000000-0000-0000-0000-000000000000"
    internal_dns_suffix  = "test.example.internal"
    trust_domain         = "test.example.internal"
    dns_allowlist_json   = jsonencode(["*.test.example.internal"])
    email_allowlist_json = jsonencode([])
    provisioners_json    = jsonencode([])
  }))

  runtime_ha_compose = templatefile("${path.module}/../../pki/config/step-ca-ha-compose.yml.tftpl", {
    aws_region            = "eu-central-1"
    cloudwatch_log_group  = "/pki/test/runtime"
    ca_fqdn               = "ca.test.example.internal"
    gitlab_broker_enabled = false
    gitlab_broker_image   = ""
    database_endpoint     = "stepca.test.rds.amazonaws.com"
    database_port         = 5432
    database_name         = "stepca"
    database_username     = "stepca"
  })

  lean_runtime_bootstrap = templatefile("${path.module}/../../modules/step-ca-ec2/templates/pki-runtime.service.tftpl", {
    artifact_bucket               = "pki-test-artifacts"
    cloudwatch_log_group_name     = "/pki/test/runtime"
    google_oidc_client_secret_arn = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:pki/google-oidc"
    gitlab_broker_jwk_secret_arn  = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:pki/gitlab-broker"
  })

  ha_runtime_bootstrap = templatefile("${path.module}/../../modules/step-ca-ha/templates/pki-runtime-ha.service.tftpl", {
    artifact_bucket               = "pki-test-artifacts"
    aws_region                    = "eu-central-1"
    database_secret_arn           = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:rds"
    google_oidc_client_secret_arn = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:pki/google-oidc"
    gitlab_broker_jwk_secret_arn  = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:pki/gitlab-broker"
    runtime_release_id            = "test-release"
  })

  google_oidc_config = jsondecode(templatefile("${path.module}/../../pki/config/ca.json.tftpl", {
    aws_region           = "eu-central-1"
    ca_fqdn              = "ca.test.example.internal"
    intermediate_key_id  = "00000000-0000-0000-0000-000000000000"
    internal_dns_suffix  = "test.example.internal"
    trust_domain         = "test.example.internal"
    dns_allowlist_json   = jsonencode(["*.test.example.internal"])
    email_allowlist_json = jsonencode(["@test.example.internal"])
    provisioners_json = jsonencode([{
      type                  = "OIDC"
      name                  = "Google Workspace"
      clientID              = "test-client.apps.googleusercontent.com"
      clientSecret          = "$${GOOGLE_OIDC_CLIENT_SECRET}"
      configurationEndpoint = "https://accounts.google.com/.well-known/openid-configuration"
      domains               = ["test.example.internal"]
      scopes                = ["openid", "email"]
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
    }])
  }))

  gitlab_broker_compose = templatefile("${path.module}/../../pki/config/step-ca-compose.yml.tftpl", {
    aws_region            = "eu-central-1"
    cloudwatch_log_group  = "/pki/test/runtime"
    ca_fqdn               = "ca.test.example.internal"
    gitlab_broker_enabled = true
    gitlab_broker_image   = "registry.test/gitlab-broker@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  })

  gitlab_broker_config = jsondecode(templatefile("${path.module}/../../pki/config/ca.json.tftpl", {
    aws_region           = "eu-central-1"
    ca_fqdn              = "ca.test.example.internal"
    intermediate_key_id  = "00000000-0000-0000-0000-000000000000"
    internal_dns_suffix  = "test.example.internal"
    trust_domain         = "test.example.internal"
    dns_allowlist_json   = jsonencode(["*.test.example.internal"])
    email_allowlist_json = jsonencode([])
    provisioners_json = jsonencode([{
      type = "JWK"
      name = "GitLab Enrollment Broker"
      key = {
        kty = "EC"
        crv = "P-256"
        x   = "test-x"
        y   = "test-y"
        kid = "gitlab-broker"
      }
      claims = {
        maxTLSCertDuration     = "1h"
        defaultTLSCertDuration = "1h"
        disableRenewal         = true
      }
    }])
  }))
}

output "validated_template_fields" {
  value = {
    ca_dns_name                             = local.ca_config.dnsNames[0]
    ca_key                                  = local.ca_config.key
    compose_has_step_ca                     = strcontains(local.runtime_compose, "step-ca")
    caddy_has_reverseproxy                  = strcontains(local.caddyfile, "reverse_proxy")
    caddy_sets_upstream_sni                 = strcontains(local.caddyfile, "tls_server_name")
    ha_uses_postgresql                      = local.ca_ha_config.db.type == "postgresql"
    ha_uses_secret_variable                 = strcontains(local.runtime_ha_compose, "$${STEP_CA_DB_PASSWORD}")
    google_uses_runtime_secret_placeholder  = local.google_oidc_config.authority.provisioners[0].clientSecret == "$${GOOGLE_OIDC_CLIENT_SECRET}"
    google_requires_verified_email_template = local.google_oidc_config.authority.provisioners[0].options.x509.templateFile == "/home/step/templates/google-workspace-x509.tpl"
    gitlab_broker_has_private_jwk_mount     = strcontains(local.gitlab_broker_compose, "/run/secrets/gitlab-broker.jwk")
    gitlab_broker_uses_jwk_provisioner      = local.gitlab_broker_config.authority.provisioners[0].type == "JWK"
    gitlab_broker_disables_renewal          = local.gitlab_broker_config.authority.provisioners[0].claims.disableRenewal
  }
}

output "runtime_compose" {
  value = local.runtime_compose
}

output "runtime_ha_compose" {
  value = local.runtime_ha_compose
}

output "gitlab_broker_compose" {
  value = local.gitlab_broker_compose
}

output "lean_runtime_bootstrap" {
  value = local.lean_runtime_bootstrap
}

output "ha_runtime_bootstrap" {
  value = local.ha_runtime_bootstrap
}
