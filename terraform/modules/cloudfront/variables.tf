variable "frontend_bucket_id" {
  description = "ID of the frontend S3 bucket"
  type        = string
}

variable "frontend_website_endpoint" {
  description = "Website endpoint of the frontend S3 bucket"
  type        = string
}

variable "aliases" {
  description = "Custom domain aliases for the distribution"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for custom domain"
  type        = string
  default     = ""
}

variable "use_custom_domain" {
  description = "Whether a custom domain is being used"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
