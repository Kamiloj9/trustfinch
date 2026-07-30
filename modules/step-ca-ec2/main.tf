data "aws_ssm_parameter" "al2023_arm64" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  ami_id = coalesce(var.ami_id, try(data.aws_ssm_parameter.al2023_arm64[0].value, null))
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "runtime" {
  name               = "${var.name}-step-ca-runtime"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json

  tags = merge(var.tags, { Name = "${var.name}-step-ca-runtime" })
}

resource "aws_iam_instance_profile" "runtime" {
  name = "${var.name}-step-ca-runtime"
  role = aws_iam_role.runtime.name
}

# Administration is through Systems Manager, never an SSH security-group rule
# or an SSH key injected into the instance.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "runtime_google_oidc_secret" {
  count = var.google_oidc_client_secret_arn == null ? 0 : 1

  statement {
    sid       = "ReadGoogleOIDCNativeClientSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oidc_client_secret_arn]
  }
}

resource "aws_iam_role_policy" "runtime_google_oidc_secret" {
  count = var.google_oidc_client_secret_arn == null ? 0 : 1

  name   = "step-ca-google-oidc-secret"
  role   = aws_iam_role.runtime.name
  policy = data.aws_iam_policy_document.runtime_google_oidc_secret[0].json
}

data "aws_iam_policy_document" "runtime_gitlab_broker_jwk_secret" {
  count = var.gitlab_broker_jwk_secret_arn == null ? 0 : 1

  statement {
    sid       = "ReadGitLabBrokerSigningJWK"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.gitlab_broker_jwk_secret_arn]
  }
}

resource "aws_iam_role_policy" "runtime_gitlab_broker_jwk_secret" {
  count = var.gitlab_broker_jwk_secret_arn == null ? 0 : 1

  name   = "step-ca-gitlab-broker-jwk"
  role   = aws_iam_role.runtime.name
  policy = data.aws_iam_policy_document.runtime_gitlab_broker_jwk_secret[0].json
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.name}-pki-artifacts-"

  tags = merge(var.tags, {
    Name      = "${var.name}-pki-artifacts"
    DataClass = "pki-public-configuration"
  })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "artifact_bucket" {
  statement {
    sid    = "RuntimeReadOnly"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.runtime.arn]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/runtime/*"]
  }

  statement {
    sid    = "RuntimeListRuntimePrefix"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.runtime.arn]
    }

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["runtime/*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.certificate_publisher_role_arns) == 0 ? [] : [1]

    content {
      sid    = "CeremonyPublishesPublicCertificatesOnly"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.certificate_publisher_role_arns
      }

      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.artifacts.arn}/runtime/certs/*.crt"]
    }
  }

  dynamic "statement" {
    for_each = length(var.artifact_signer_role_arns) == 0 ? [] : [1]

    content {
      sid    = "ReleaseSignerReadsRuntimeArtifacts"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.artifact_signer_role_arns
      }

      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.artifacts.arn}/runtime/*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.artifact_signer_role_arns) == 0 ? [] : [1]

    content {
      sid    = "ReleaseSignerListsRuntimeArtifacts"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.artifact_signer_role_arns
      }

      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.artifacts.arn]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["runtime/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.artifact_signer_role_arns) == 0 ? [] : [1]

    content {
      sid    = "ReleaseSignerPublishesSignedManifestOnly"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.artifact_signer_role_arns
      }

      actions = ["s3:PutObject"]
      resources = [
        "${aws_s3_bucket.artifacts.arn}/runtime/runtime.manifest",
        "${aws_s3_bucket.artifacts.arn}/runtime/runtime.manifest.sig",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifact_bucket.json
}

resource "aws_security_group" "runtime" {
  name_prefix = "${var.name}-step-ca-"
  description = "Permit HTTPS to the step-ca endpoint only."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from approved networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_https_cidrs
  }

  egress {
    description = "Outbound access for AWS APIs, package install, and public ACME TLS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-step-ca" })
}

resource "aws_instance" "runtime" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  iam_instance_profile        = aws_iam_instance_profile.runtime.name
  vpc_security_group_ids      = [aws_security_group.runtime.id]
  associate_public_ip_address = true
  monitoring                  = true
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size

    tags = merge(var.tags, {
      Name      = "${var.name}-step-ca-state"
      Role      = "step-ca-state"
      DataClass = "pki-issuance-state"
    })
  }

  user_data = templatefile("${path.module}/templates/pki-runtime.service.tftpl", {
    artifact_bucket                 = aws_s3_bucket.artifacts.id
    artifact_verification_enabled   = var.artifact_verification_enabled
    artifact_signing_public_key_pem = coalesce(var.artifact_signing_public_key_pem, "")
    artifact_verifier_script        = file("${path.module}/../../pki/runtime/verify-runtime-artifacts.sh")
    artifact_signer_role_arns       = var.artifact_signer_role_arns
    cloudwatch_log_group_name       = var.cloudwatch_log_group_name
    google_oidc_client_secret_arn   = coalesce(var.google_oidc_client_secret_arn, "")
    gitlab_broker_jwk_secret_arn    = coalesce(var.gitlab_broker_jwk_secret_arn, "")
    pki_name                        = var.name
  })

  lifecycle {
    precondition {
      condition     = !var.artifact_verification_enabled || var.artifact_signing_public_key_pem != null
      error_message = "artifact_signing_public_key_pem is required when artifact_verification_enabled is true."
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-step-ca"
    Role = "step-ca"
  })
}

resource "aws_eip" "runtime" {
  domain   = "vpc"
  instance = aws_instance.runtime.id

  tags = merge(var.tags, { Name = "${var.name}-step-ca" })
}
