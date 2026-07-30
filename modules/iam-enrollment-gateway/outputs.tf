output "api_endpoint" {
  value       = aws_apigatewayv2_stage.default.invoke_url
  description = "HTTPS endpoint. Every request must be SigV4-signed by a role with the exported invoke policy."
}

output "invoke_policy_json" {
  value       = data.aws_iam_policy_document.caller_invoke.json
  description = "Attach this exact policy only to reviewed IAM roles that appear in the broker identity mapping."
}

output "invoke_arn" {
  value       = "${aws_apigatewayv2_api.this.execution_arn}/*/POST/1.0/enroll/iam"
  description = "Exact execute-api ARN that callers need for execute-api:Invoke."
}

output "lambda_role_arn" {
  value = aws_iam_role.runtime.arn
}
