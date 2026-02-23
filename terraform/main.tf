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

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ── IAM ROLES ─────────────────────────────────────────────────────────────────
module "security" {
  source = "./modules/security"

  project_name     = var.project_name
  eks_cluster_name = var.eks_cluster_name
  # eks_oidc_provider is PLACEHOLDER until EKS cluster is created in Phase 4
  # After Phase 4: terraform apply updates trust policies with real OIDC URL
}
