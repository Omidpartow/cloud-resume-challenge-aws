terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket for static website
resource "aws_s3_bucket" "resume_site" {
  bucket = "omidpartow-resume-${random_id.bucket_suffix.hex}"

  tags = {
    Name  = "omidpartow-resume-site"
    Owner = "Omid Partow"
  }
}

resource "aws_s3_bucket_website_configuration" "resume_site" {
  bucket = aws_s3_bucket.resume_site.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "resume_site" {
  bucket = aws_s3_bucket.resume_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "resume_site" {
  bucket = aws_s3_bucket.resume_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.resume_site.arn}/*"
      }
    ]
  })
}

# CloudFront origin access identity
resource "aws_cloudfront_origin_access_identity" "resume_site" {
  comment = "OAI for Omid Partow resume site"
}

# CloudFront distribution in front of S3
resource "aws_cloudfront_distribution" "resume_site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.resume_site.bucket_regional_domain_name
    origin_id   = "S3-resume-site"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.resume_site.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    target_origin_id       = "S3-resume-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name  = "omidpartow-cloud-resume"
    Owner = "Omid Partow"
  }
}

# API + Lambda + DynamoDB for visitor counter (skeleton only, optional to deploy)
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "ResumeVisitorCounter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "resume-counter-lambda-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource = aws_dynamodb_table.visitor_counter.arn
    }]
  })
}

# Placeholder Lambda (you can upload real zip later)
resource "aws_lambda_function" "visitor_counter" {
  filename      = "lambda.zip"
  function_name = "ResumeVisitorCounter"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }
}

resource "aws_apigatewayv2_api" "resume_api" {
  name          = "resume-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "visitor_integration" {
  api_id             = aws_apigatewayv2_api.resume_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.visitor_counter.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "visitor_route" {
  api_id    = aws_apigatewayv2_api.resume_api.id
  route_key = "GET /counter"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_integration.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.resume_api.execution_arn}//"
}

output "website_bucket" {
  value = aws_s3_bucket.resume_site.bucket
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.resume_site.domain_name
}

output "api_url" {
  value = aws_apigatewayv2_api.resume_api.api_endpoint
}
