output "eks_node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_instance_profile_name" {
  description = "EKS node instance profile name"
  value       = aws_iam_instance_profile.eks_node.name
}

output "eks_pod_api_role_arn" {
  description = "IRSA role ARN for FastAPI pods"
  value       = aws_iam_role.eks_pod_api.arn
}

output "eks_pod_lbc_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.eks_pod_lbc.arn
}

output "eks_pod_ca_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler"
  value       = aws_iam_role.eks_pod_ca.arn
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN (application-level)"
  value       = aws_iam_role.ecs_task.arn
}

output "codebuild_build_role_arn" {
  description = "CodeBuild build role ARN"
  value       = aws_iam_role.codebuild_build.arn
}

output "codebuild_deploy_role_arn" {
  description = "CodeBuild deploy role ARN (kubectl stage — add to aws-auth)"
  value       = aws_iam_role.codebuild_deploy.arn
}

output "codedeploy_role_arn" {
  description = "CodeDeploy role ARN"
  value       = aws_iam_role.codedeploy.arn
}

output "codepipeline_role_arn" {
  description = "CodePipeline role ARN"
  value       = aws_iam_role.codepipeline.arn
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda.arn
}
