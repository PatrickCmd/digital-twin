output "acm_certificate_arn" {
  description = "ARN of the existing ACM certificate"
  value       = data.aws_acm_certificate.site.arn
}

output "domain_aliases" {
  description = "List of domain aliases for CloudFront"
  value       = [var.subdomain]
}
