data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS MANAGER SECRETS
# Created with placeholder values now.
# RDS secret updated in Phase 5 after RDS endpoint is known.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.project_name}/rds/credentials"
  description             = "RDS PostgreSQL credentials for platform API"
  recovery_window_in_days = 0  # Immediate deletion on destroy (demo)

  tags = { Name = "${var.project_name}-rds-secret" }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  # Placeholder — updated in Phase 5 with real RDS endpoint
  secret_string = jsonencode({
    username = "app_user"
    password = "PLACEHOLDER_UPDATED_AFTER_RDS"
    host     = "PLACEHOLDER_UPDATED_AFTER_RDS"
    port     = 5432
    dbname   = "appdb"
  })

  # Ignore future changes — the secret is updated externally after RDS creation
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.project_name}/redis/connection"
  description             = "ElastiCache Redis connection details"
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-redis-secret" }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  # Placeholder — updated in Phase 5 after ElastiCache is created
  secret_string = jsonencode({
    host = "PLACEHOLDER_UPDATED_AFTER_ELASTICACHE"
    port = 6379
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${var.project_name}/app/config"
  description             = "Application configuration (non-sensitive)"
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-app-config-secret" }
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id

  secret_string = jsonencode({
    environment     = "demo"
    log_level       = "INFO"
    app_name        = "aws-production-platform"
    aws_region      = local.region
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDTRAIL
# Single trail (free tier), all-region, management events only.
# S3 destination + CloudWatch Logs integration + log integrity validation.
# ─────────────────────────────────────────────────────────────────────────────

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-logs-${local.account_id}"
  force_destroy = true

  tags = { Name = "${var.project_name}-cloudtrail-logs" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudTrail requires a specific bucket policy to allow log delivery
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# CloudWatch Log Group for CloudTrail real-time monitoring
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/cloudtrail/${var.project_name}"
  retention_in_days = 7

  tags = { Name = "${var.project_name}-cloudtrail-logs" }
}

# IAM role for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cw" {
  name = "${var.project_name}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  name = "${var.project_name}-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# The CloudTrail trail itself
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true  # SHA-256 integrity validation

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn

  # Management events only (free) — no data events (costly)
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = { Name = "${var.project_name}-audit-trail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
