terraform {
  required_version = ">= 1.13.0, < 2.0.0"
}

locals {
  ca_config = jsondecode(templatefile("${path.module}/../../pki/config/ca.json.tftpl", {
    aws_region          = "eu-central-1"
    ca_fqdn             = "ca.test.example.internal"
    intermediate_key_id = "00000000-0000-0000-0000-000000000000"
    internal_dns_suffix = "test.example.internal"
    trust_domain        = "test.example.internal"
  }))

  runtime_compose = templatefile("${path.module}/../../pki/config/step-ca-compose.yml.tftpl", {
    aws_region           = "eu-central-1"
    cloudwatch_log_group = "/pki/test/runtime"
  })

  caddyfile = templatefile("${path.module}/../../pki/config/Caddyfile.tftpl", {
    ca_fqdn = "ca.test.example.internal"
  })
}

output "validated_template_fields" {
  value = {
    ca_dns_name             = local.ca_config.dnsNames[0]
    ca_key                  = local.ca_config.key
    compose_has_step_ca     = strcontains(local.runtime_compose, "step-ca")
    caddy_has_reverseproxy  = strcontains(local.caddyfile, "reverse_proxy")
    caddy_sets_upstream_sni = strcontains(local.caddyfile, "tls_server_name")
  }
}

output "runtime_compose" {
  value = local.runtime_compose
}
