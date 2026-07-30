data "aws_iam_policy_document" "assume_lambda" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "runtime" {
  name               = "${var.name}-iam-enrollment-broker"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

resource "aws_cloudwatch_log_group" "runtime" {
  name              = "/pki/${var.name}/iam-enrollment-broker"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_s3_bucket" "configuration" {
  bucket_prefix = "${var.name}-iam-broker-config-"
  tags          = merge(var.tags, { Name = "${var.name}-iam-broker-config" })
}

resource "aws_s3_bucket_public_access_block" "configuration" {
  bucket                  = aws_s3_bucket.configuration.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "configuration" {
  bucket = aws_s3_bucket.configuration.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "configuration" {
  bucket = aws_s3_bucket.configuration.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "configuration" {
  bucket                 = aws_s3_bucket.configuration.id
  key                    = "iam-enrollment-broker/config.json"
  content                = var.broker_config_json
  content_type           = "application/json"
  server_side_encryption = "AES256"
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid       = "ReadReviewedBrokerConfiguration"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [aws_s3_object.configuration.arn]
  }

  statement {
    sid       = "ReadBrokerSigningJWK"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.jwk_secret_arn]
  }

  statement {
    sid       = "WriteBrokerLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.runtime.arn}:*"]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "iam-enrollment-broker-runtime"
  role   = aws_iam_role.runtime.name
  policy = data.aws_iam_policy_document.runtime.json
}

resource "aws_lambda_function" "this" {
  function_name                  = "${var.name}-iam-enrollment-broker"
  description                    = "Issues only reviewed certificate identities for API Gateway SigV4-authenticated IAM roles."
  package_type                   = "Image"
  image_uri                      = var.lambda_image_uri
  role                           = aws_iam_role.runtime.arn
  timeout                        = 15
  memory_size                    = 256
  reserved_concurrent_executions = var.reserved_concurrent_executions
  architectures                  = ["arm64"]

  environment {
    variables = {
      IAM_BROKER_CONFIG_BUCKET  = aws_s3_bucket.configuration.id
      IAM_BROKER_CONFIG_KEY     = aws_s3_object.configuration.key
      IAM_BROKER_JWK_SECRET_ARN = var.jwk_secret_arn
    }
  }

  depends_on = [aws_iam_role_policy.runtime, aws_s3_object.configuration]
  tags       = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-iam-enrollment"
  protocol_type = "HTTP"
  description   = "SigV4-protected IAM certificate enrollment gateway."
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 15000
}

resource "aws_apigatewayv2_route" "enroll" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /1.0/enroll/iam"
  authorization_type = "AWS_IAM"
  target             = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.runtime.arn
    format = jsonencode({
      request_id = "$context.requestId"
      route_key  = "$context.routeKey"
      status     = "$context.status"
      source_ip  = "$context.identity.sourceIp"
    })
  }

  tags = var.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/POST/1.0/enroll/iam"
}

data "aws_iam_policy_document" "caller_invoke" {
  statement {
    sid       = "InvokeIAMCertificateEnrollment"
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_apigatewayv2_api.this.execution_arn}/*/POST/1.0/enroll/iam"]
  }
}
