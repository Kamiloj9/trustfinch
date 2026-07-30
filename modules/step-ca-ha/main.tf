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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-step-ca-alb-"
  description = "HTTPS to the step-ca ALB."
  vpc_id      = var.vpc_id

  ingress {
    description = "Approved CA clients"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_https_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-step-ca-alb" })
}

resource "aws_security_group" "nodes" {
  name_prefix = "${var.name}-step-ca-node-"
  description = "TLS from ALB to step-ca nodes."
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB to step-ca"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-step-ca-node" })
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
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifact_bucket.json
}

data "aws_iam_policy_document" "runtime_bootstrap" {
  statement {
    sid     = "ReadManagedRuntimeSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [var.database_secret_arn],
      var.google_oidc_client_secret_arn == null ? [] : [var.google_oidc_client_secret_arn],
    )
  }

  statement {
    sid       = "WriteRuntimeLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${var.cloudwatch_log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "runtime_bootstrap" {
  name   = "step-ca-ha-bootstrap"
  role   = aws_iam_role.runtime.name
  policy = data.aws_iam_policy_document.runtime_bootstrap.json
}

resource "aws_lb" "this" {
  name                       = "${var.name}-step-ca"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.name}-step-ca" })
}

resource "aws_lb_target_group" "this" {
  name_prefix = "${substr(var.name, 0, 20)}-ca-"
  port        = 9000
  protocol    = "HTTPS"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled  = true
    protocol = "HTTPS"
    path     = "/health"
    matcher  = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-step-ca-"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.nodes.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.runtime.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = 20
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/pki-runtime-ha.service.tftpl", {
    artifact_bucket               = aws_s3_bucket.artifacts.id
    aws_region                    = var.aws_region
    database_secret_arn           = var.database_secret_arn
    google_oidc_client_secret_arn = coalesce(var.google_oidc_client_secret_arn, "")
    runtime_release_id            = var.runtime_release_id
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name = "${var.name}-step-ca"
      Role = "step-ca"
    })
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.name}-step-ca"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 300
      min_healthy_percentage = 50
      max_healthy_percentage = 100
      skip_matching          = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-step-ca"
    propagate_at_launch = true
  }

  tag {
    key                 = "RuntimeRelease"
    value               = var.runtime_release_id
    propagate_at_launch = true
  }
}
