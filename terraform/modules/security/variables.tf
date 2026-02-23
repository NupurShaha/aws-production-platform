variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name (used for IAM resource ARNs)"
  type        = string
}

variable "eks_oidc_provider" {
  description = "EKS OIDC provider URL without https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX)"
  type        = string
  default     = "PLACEHOLDER"
  # This is set to PLACEHOLDER now and updated after EKS cluster is created.
  # The IRSA roles that depend on this will be updated in Phase 4.
}
