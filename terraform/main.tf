data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # prod: digital-twin.patrickcmd.dev
  # test: test-digital-twin.patrickcmd.dev
  # dev:  dev-digital-twin.patrickcmd.dev
  custom_subdomain = var.environment == "prod" ? "${var.subdomain_prefix}.${var.root_domain}" : "${var.environment}-${var.subdomain_prefix}.${var.root_domain}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Browser origins allowed to call the API: the CloudFront domain, the custom
  # domain when enabled, and localhost outside prod for local frontend dev.
  site_origins = concat(
    ["https://${module.cloudfront.domain_name}"],
    var.use_custom_domain ? ["https://${local.custom_subdomain}"] : [],
    var.environment == "prod" ? [] : ["http://localhost:3000"],
  )
}

# S3 buckets (memory + frontend)
module "s3" {
  source = "./modules/s3"

  name_prefix = local.name_prefix
  account_id  = data.aws_caller_identity.current.account_id
  common_tags = local.common_tags
}

# CloudFront distribution
module "cloudfront" {
  source = "./modules/cloudfront"

  frontend_bucket_id        = module.s3.frontend_bucket_id
  frontend_website_endpoint = module.s3.frontend_website_endpoint
  aliases                   = var.use_custom_domain ? module.dns[0].domain_aliases : []
  acm_certificate_arn       = var.use_custom_domain ? module.dns[0].acm_certificate_arn : ""
  use_custom_domain         = var.use_custom_domain
  common_tags               = local.common_tags
}

# Lambda function
module "lambda" {
  source = "./modules/lambda"

  name_prefix             = local.name_prefix
  timeout                 = var.lambda_timeout
  bedrock_model_id        = var.bedrock_model_id
  s3_memory_bucket_id     = module.s3.memory_bucket_id
  s3_memory_bucket_arn    = module.s3.memory_bucket_arn
  cors_origins            = join(",", local.site_origins)
  deployment_package_path = "${path.module}/../backend/lambda-deployment.zip"
  enable_rate_limit_table = var.enable_rate_limit_table
  common_tags             = local.common_tags
}

# API Gateway
module "api_gateway" {
  source = "./modules/api_gateway"

  name_prefix          = local.name_prefix
  lambda_function_name = module.lambda.function_name
  lambda_invoke_arn    = module.lambda.invoke_arn
  cors_origins         = local.site_origins
  throttle_burst_limit = var.api_throttle_burst_limit
  throttle_rate_limit  = var.api_throttle_rate_limit
  common_tags          = local.common_tags
}

# DNS (optional - only when using custom domain)
module "dns" {
  count  = var.use_custom_domain ? 1 : 0
  source = "./modules/dns"

  providers = {
    aws = aws.us_east_1
  }

  root_domain               = var.root_domain
  subdomain                 = local.custom_subdomain
  cloudfront_domain_name    = module.cloudfront.domain_name
  cloudfront_hosted_zone_id = module.cloudfront.hosted_zone_id
  common_tags               = local.common_tags
}
