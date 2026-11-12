terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Package Python Lambda function

data "archive_file" "get_load" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/get_load"
  output_path = "${path.module}/get_load.zip"
}

# IAM Role for Lambda

resource "aws_iam_role" "lambda_role" {
  name = "serverless-load-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

# Allow Lambda to write CloudWatch logs

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role = aws_iam_role.lambda_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function

resource "aws_lambda_function" "get_load" {
  function_name = "serverless-get-load"

  filename         = data.archive_file.get_load.output_path
  source_code_hash = data.archive_file.get_load.output_base64sha256

  role = aws_iam_role.lambda_role.arn

  handler = "app.handler"
  runtime = "python3.12"

  timeout     = 10
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging
  ]

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.loads.name
    }
  }
}

# API Gateway HTTP API

resource "aws_apigatewayv2_api" "http_api" {
  name          = "serverless-load-api"
  protocol_type = "HTTP"
}

# Lambda Integration

resource "aws_apigatewayv2_integration" "get_load" {
  api_id = aws_apigatewayv2_api.http_api.id

  integration_type   = "AWS_PROXY"
  integration_method = "POST"

  integration_uri = aws_lambda_function.get_load.invoke_arn

  payload_format_version = "2.0"
}

# API Route

resource "aws_apigatewayv2_route" "get_load" {
  api_id = aws_apigatewayv2_api.http_api.id

  route_key = "GET /loads/{loadNumber}"

  target = "integrations/${aws_apigatewayv2_integration.get_load.id}"
}



# Allow API Gateway to invoke Lambda

resource "aws_lambda_permission" "api_gateway" {
  statement_id = "AllowAPIGatewayInvoke"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.get_load.function_name

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# API Gateway Stage

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.http_api.id

  name = "$default"

  auto_deploy = true
}

resource "aws_dynamodb_table" "loads" {
  name         = "serverless-loads"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "loadNumber"
  attribute {
    name = "loadNumber"
    type = "S"
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "serverless-get-load-dynamodb"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.loads.arn
      }
    ]
  })

}

resource "aws_apigatewayv2_route" "create_load" {

  api_id = aws_apigatewayv2_api.http_api.id

  route_key = "POST /loads"

  target = "integrations/${aws_apigatewayv2_integration.get_load.id}"

}