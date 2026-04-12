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

variable "cors_origins" {
  description = "Allowed CORS origins for the Lambda function"
  type        = string
}

variable "deployment_package_path" {
  description = "Path to the Lambda deployment zip file"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
