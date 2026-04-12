variable "root_domain" {
  description = "Apex domain name (e.g. patrickcmd.dev)"
  type        = string
}

variable "subdomain" {
  description = "Full subdomain to create (e.g. digital-twin.patrickcmd.dev)"
  type        = string
}

variable "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
