# Look up existing hosted zone
data "aws_route53_zone" "root" {
  name         = var.root_domain
  private_zone = false
}

# Look up existing ACM certificate (must be in us-east-1 for CloudFront)
data "aws_acm_certificate" "site" {
  domain      = var.root_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

# DNS alias records for subdomain
resource "aws_route53_record" "subdomain" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = var.subdomain
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "subdomain_ipv6" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = var.subdomain
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}
