# ── DATA SOURCES ──────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. EKS NODE ROLE
# Attached to EC2 instances that form EKS worker nodes.
# Deliberately minimal — no application permissions here.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Instance profile — wraps the node role for EC2 attachment
resource "aws_iam_instance_profile" "eks_node" {
  name = "${var.project_name}-eks-node-profile"
  role = aws_iam_role.eks_node.name
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. EKS POD ROLE — API (IRSA)
# Used by FastAPI pods + X-Ray sidecar.
# Scoped to: Secrets Manager reads + X-Ray writes only.
# Trust policy scoped to specific ServiceAccount in specific namespace.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_pod_api" {
  name = "${var.project_name}-eks-pod-api-role"

  # Trust policy references the EKS OIDC provider.
  # The OIDC URL is injected after EKS cluster creation.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.eks_oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider}:sub" = "system:serviceaccount:app:api-sa"
          "${var.eks_oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eks_pod_api" {
  name = "${var.project_name}-eks-pod-api-policy"
  role = aws_iam_role.eks_pod_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        # Scoped to this project's secrets only
        Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}/*"
      },
      {
        Sid    = "XRayWrite"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. EKS POD ROLE — AWS LOAD BALANCER CONTROLLER (IRSA)
# LBC needs broad EC2/ELB permissions to provision ALBs from Ingress objects.
# Policy fetched from official AWS repo (pinned version).
# ─────────────────────────────────────────────────────────────────────────────
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name        = "${var.project_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.lbc_iam_policy.response_body
}

resource "aws_iam_role" "eks_pod_lbc" {
  name = "${var.project_name}-eks-pod-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.eks_oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${var.eks_oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_pod_lbc" {
  role       = aws_iam_role.eks_pod_lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. EKS POD ROLE — CLUSTER AUTOSCALER (IRSA)
# Allows CA to discover and scale ASGs backing the EKS node group.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_pod_ca" {
  name = "${var.project_name}-eks-pod-ca-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.eks_oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${var.eks_oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eks_pod_ca" {
  name = "${var.project_name}-eks-pod-ca-policy"
  role = aws_iam_role.eks_pod_ca.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeInstanceTypes",
        "eks:DescribeNodegroup"
      ]
      Resource = "*"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. ECS TASK EXECUTION ROLE
# Used by the ECS control plane: pull images from ECR, write logs to CW.
# NOT the application role — this is infrastructure-level.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to fetch secrets (for injecting into task env)
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SecretsManagerFetch"
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}/*"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. ECS TASK ROLE (application-level)
# Assumed by the worker application code itself inside the container.
# Only what the app actually needs to call.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SecretsManagerRead"
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}/*"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. CODEBUILD BUILD ROLE
# Used by the build stage: docker build, ECR push, CloudFront invalidation.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codebuild_build" {
  name = "${var.project_name}-codebuild-build-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_build" {
  name = "${var.project_name}-codebuild-build-policy"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          "arn:aws:ecr:${local.region}:${local.account_id}:repository/${var.project_name}/api",
          "arn:aws:ecr:${local.region}:${local.account_id}:repository/${var.project_name}/worker"
        ]
      },
      {
        Sid    = "S3Artifacts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}",
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}/*"
        ]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. CODEBUILD DEPLOY ROLE (kubectl stage)
# Used by the EKS deploy CodeBuild project.
# Must be added to aws-auth ConfigMap in EKS after cluster creation.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codebuild_deploy" {
  name = "${var.project_name}-codebuild-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_deploy" {
  name = "${var.project_name}-codebuild-deploy-policy"
  role = aws_iam_role.codebuild_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribe"
        Effect = "Allow"
        Action = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${local.region}:${local.account_id}:cluster/${var.eks_cluster_name}"
      },
      {
        Sid    = "S3Artifacts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}",
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}/*"
        ]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. CODEDEPLOY ROLE
# Used by CodeDeploy for ECS blue-green deployments only.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. LAMBDA EXECUTION ROLE
# Used by both Lambda functions: ecs-restart and ecs-scheduler.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSControl"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.project_name}-alerts"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CODEPIPELINE ROLE
# Orchestrates the pipeline: triggers CodeBuild, CodeDeploy, reads S3.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Artifacts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning", "s3:GetObjectVersion"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}",
          "arn:aws:s3:::${var.project_name}-cicd-artifacts-${local.account_id}/*"
        ]
      },
      {
        Sid    = "CodeBuildTrigger"
        Effect = "Allow"
        Action = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = "*"
      },
      {
        Sid    = "CodeDeployTrigger"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetDeploymentConfig",
          "ecs:RegisterTaskDefinition",
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeStarConnection"
        Effect = "Allow"
        Action = ["codestar-connections:UseConnection"]
        Resource = "*"
      }
    ]
  })
}
