output "api_repository_url" {
  description = "ECR repository URL for the API image"
  value       = aws_ecr_repository.api.repository_url
}

output "worker_repository_url" {
  description = "ECR repository URL for the worker image"
  value       = aws_ecr_repository.worker.repository_url
}

output "registry_url" {
  description = "ECR registry URL (account.dkr.ecr.region.amazonaws.com)"
  value       = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
