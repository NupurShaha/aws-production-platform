provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-production-platform"
      Owner       = "nupur-shaha"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}
