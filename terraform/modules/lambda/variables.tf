variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
}

variable "s3_memory_bucket_id" {
  description = "S3 bucket ID for conversation memory"
  type        = string
}

variable "s3_memory_bucket_arn" {
  description = "S3 bucket ARN for conversation memory"
  type        = string
}

variable "cors_origins" {
  description = "Comma-separated allowed CORS origins for the Lambda function"
  type        = string
}

variable "deployment_package_path" {
  description = "Path to the Lambda deployment zip file"
  type        = string
}

variable "max_message_chars" {
  description = "Maximum characters accepted in a single chat message"
  type        = number
  default     = 2000
}

variable "max_session_messages" {
  description = "Maximum stored messages (user + assistant) per session before a new chat is required"
  type        = number
  default     = 60
}

variable "rate_limit_requests" {
  description = "Requests allowed per client per window on the chat routes"
  type        = number
  default     = 20
}

variable "rate_limit_window_seconds" {
  description = "Rate-limit window length in seconds"
  type        = number
  default     = 600
}

variable "enable_rate_limit_table" {
  description = "Create a DynamoDB table so the per-client rate limit is shared across Lambda instances. Without it the limit is per warm container only."
  type        = bool
  default     = false
}

variable "enable_contact_email" {
  description = "Email contact-form messages through Amazon SES. Requires contact_from_email to be a verified SES identity."
  type        = bool
  default     = false
}

variable "contact_from_email" {
  description = "Verified SES sender address for contact-form email"
  type        = string
  default     = ""
}

variable "contact_to_email" {
  description = "Recipient of contact-form email"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
