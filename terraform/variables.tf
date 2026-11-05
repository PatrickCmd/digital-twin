variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
  default     = "global.amazon.nova-2-lite-v1:0"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 10
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
  default     = 5
}

variable "use_custom_domain" {
  description = "Attach a custom domain to CloudFront"
  type        = bool
  default     = false
}

variable "root_domain" {
  description = "Apex domain name, e.g. patrickcmd.dev"
  type        = string
  default     = ""
}

variable "subdomain_prefix" {
  description = "Subdomain prefix (e.g. digital-twin). Environment prefix is auto-added for dev/test."
  type        = string
  default     = "digital-twin"
}

variable "enable_rate_limit_table" {
  description = "Create a DynamoDB table (pay-per-request) so the per-client chat rate limit is shared across Lambda instances"
  type        = bool
  default     = false
}

variable "enable_contact_email" {
  description = "Send contact-form messages by email through Amazon SES (sender must be a verified SES identity)"
  type        = bool
  default     = false
}

variable "contact_from_email" {
  description = "Verified SES sender address used when enable_contact_email is true"
  type        = string
  default     = ""
}

variable "contact_to_email" {
  description = "Where contact-form messages are delivered when enable_contact_email is true"
  type        = string
  default     = ""
}
