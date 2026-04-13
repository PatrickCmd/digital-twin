terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_profile" {
  description = "AWS CLI profile for local development (leave empty for CI/CD with OIDC)"
  type        = string
  default     = ""
}

provider "aws" {
  profile = var.aws_profile != "" ? var.aws_profile : null
}

provider "aws" {
  alias   = "us_east_1"
  profile = var.aws_profile != "" ? var.aws_profile : null
  region  = "us-east-1"
}
