output "rds_secret_arn" {
  description = "ARN of the RDS credentials secret"
  value       = aws_secretsmanager_secret.rds.arn
}

output "redis_secret_arn" {
  description = "ARN of the Redis connection secret"
  value       = aws_secretsmanager_secret.redis.arn
}

output "app_config_secret_arn" {
  description = "ARN of the app config secret"
  value       = aws_secretsmanager_secret.app_config.arn
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail S3 bucket name"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_name" {
  description = "CloudTrail trail name"
  value       = aws_cloudtrail.main.name
}
