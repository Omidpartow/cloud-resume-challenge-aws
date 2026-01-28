# Cloud Resume Challenge - AWS Serverless

Serverless resume website + visitor counter (Cloud Resume Challenge style) deployed with Terraform.

## What this project includes

- S3 bucket configured for static website hosting
- CloudFront distribution in front of S3 (HTTPS, global CDN)
- DynamoDB table for visitor counter
- Lambda + API Gateway HTTP API for incrementing/reading the count (infrastructure scaffold)
- All infrastructure defined as code with Terraform

## Architecture

Browser → CloudFront → S3 (index.html)

Browser → CloudFront → API Gateway → Lambda → DynamoDB (visitor counter)

## How to deploy (optional)

```bash
terraform init
terraform apply
