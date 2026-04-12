output "api_endpoint" {
  description = "URL of the API Gateway endpoint"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_apigatewayv2_api.main.execution_arn
}
