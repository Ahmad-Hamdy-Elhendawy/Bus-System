# ---------------------------------------------------------------------
# Cloud-Based Bus Pass System - Infrastructure as Code
# AWS Provider configuration
# ---------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# ---------------------------------------------------------------------
# DYNAMODB: Tickets table
# ---------------------------------------------------------------------
resource "aws_dynamodb_table" "tickets" {
  name         = "Tickets"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticket_code"

  attribute {
    name = "ticket_code"
    type = "S"
  }

  attribute {
    name = "user_email"
    type = "S"
  }

  global_secondary_index {
    name            = "user_email-index"
    hash_key        = "user_email"
    projection_type = "ALL"
  }

  tags = {
    Name        = "BusTicketTable"
    Environment = "Production"
    Project     = "CloudBusPassSystem"
  }
}

# ---------------------------------------------------------------------
# S3 BUCKET: Static website hosting
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "website" {
  bucket = "bus-ticket"

  tags = {
    Name        = "BusTicketWebsite"
    Environment = "Production"
    Project     = "CloudBusPassSystem"
  }
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          "${aws_s3_bucket.website.arn}/index.html",
          "${aws_s3_bucket.website.arn}/success.html",
          "${aws_s3_bucket.website.arn}/cancel.html"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------
# LAMBDA IAM ROLE
# ---------------------------------------------------------------------
resource "aws_iam_role" "lambda_execution" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# ---------------------------------------------------------------------
# LAMBDA FUNCTIONS (without code - to be uploaded separately)
# ---------------------------------------------------------------------
resource "aws_lambda_function" "create_checkout" {
  filename         = "../lambdas/create-checkout.zip"
  function_name    = "create-checkout"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      STRIPE_SECRET_KEY = var.stripe_secret_key
    }
  }

  tags = {
    Project = "CloudBusPassSystem"
  }
}

resource "aws_lambda_function" "webhook" {
  filename         = "../lambdas/webhook.zip"
  function_name    = "webhook"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      STRIPE_WEBHOOK_SECRET = var.stripe_webhook_secret
    }
  }

  tags = {
    Project = "CloudBusPassSystem"
  }
}

resource "aws_lambda_function" "validate" {
  filename         = "../lambdas/validate.zip"
  function_name    = "validate"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 5
  memory_size      = 128

  tags = {
    Project = "CloudBusPassSystem"
  }
}

resource "aws_lambda_function" "get_ticket" {
  filename         = "../lambdas/get-ticket.zip"
  function_name    = "get-ticket"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 5
  memory_size      = 128

  tags = {
    Project = "CloudBusPassSystem"
  }
}

# ---------------------------------------------------------------------
# API GATEWAY
# ---------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "bus_ticket_api" {
  name        = "BusTicketAPI"
  description = "API for Cloud-Based Bus Pass System"
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Project = "CloudBusPassSystem"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.bus_ticket_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.create_checkout.id,
      aws_api_gateway_resource.webhook.id,
      aws_api_gateway_resource.validate.id,
      aws_api_gateway_resource.get_ticket.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.bus_ticket_api.id
  stage_name    = "prod"
}

# Route 1: /create_checkout
resource "aws_api_gateway_resource" "create_checkout" {
  rest_api_id = aws_api_gateway_rest_api.bus_ticket_api.id
  parent_id   = aws_api_gateway_rest_api.bus_ticket_api.root_resource_id
  path_part   = "create_checkout"
}

resource "aws_api_gateway_method" "create_checkout_post" {
  rest_api_id   = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id   = aws_api_gateway_resource.create_checkout.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_checkout_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id             = aws_api_gateway_resource.create_checkout.id
  http_method             = aws_api_gateway_method.create_checkout_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_checkout.invoke_arn
}

resource "aws_lambda_permission" "create_checkout_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_checkout.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bus_ticket_api.execution_arn}/*/POST/create_checkout"
}

# Route 2: /webhook
resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.bus_ticket_api.id
  parent_id   = aws_api_gateway_rest_api.bus_ticket_api.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
}

resource "aws_lambda_permission" "webhook_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bus_ticket_api.execution_arn}/*/POST/webhook"
}

# Route 3: /validate
resource "aws_api_gateway_resource" "validate" {
  rest_api_id = aws_api_gateway_rest_api.bus_ticket_api.id
  parent_id   = aws_api_gateway_rest_api.bus_ticket_api.root_resource_id
  path_part   = "validate"
}

resource "aws_api_gateway_method" "validate_post" {
  rest_api_id   = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id   = aws_api_gateway_resource.validate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "validate_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id             = aws_api_gateway_resource.validate.id
  http_method             = aws_api_gateway_method.validate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.validate.invoke_arn
}

resource "aws_lambda_permission" "validate_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bus_ticket_api.execution_arn}/*/POST/validate"
}

# Route 4: /get-ticket
resource "aws_api_gateway_resource" "get_ticket" {
  rest_api_id = aws_api_gateway_rest_api.bus_ticket_api.id
  parent_id   = aws_api_gateway_rest_api.bus_ticket_api.root_resource_id
  path_part   = "get-ticket"
}

resource "aws_api_gateway_method" "get_ticket_get" {
  rest_api_id   = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id   = aws_api_gateway_resource.get_ticket.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_ticket_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bus_ticket_api.id
  resource_id             = aws_api_gateway_resource.get_ticket.id
  http_method             = aws_api_gateway_method.get_ticket_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_ticket.invoke_arn
}

resource "aws_lambda_permission" "get_ticket_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_ticket.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bus_ticket_api.execution_arn}/*/GET/get-ticket"
}

# ---------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------
output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "website_url" {
  description = "S3 static website URL"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.tickets.name
}
