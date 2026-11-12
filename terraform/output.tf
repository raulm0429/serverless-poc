output "api_endpoint" {
  description = "API Gateway endpoint"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "lambda_function_name" {
  value = aws_lambda_function.get_load.function_name
}

output "api_route" {
  value = "GET /loads/{loadNumber}"
}