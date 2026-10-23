# =============================================================================
# Core Infrastructure Outputs
# =============================================================================

output "region" {
  description = "AWS region the infrastructure lives in."
  value       = var.region
}

output "vpc_id" {
  description = "Identifier of the provisioned VPC."
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the provisioned VPC."
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "Primary IPv4 CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (for ALBs and internet-facing ingress)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (for EKS worker nodes and workloads)."
  value       = aws_subnet.private[*].id
}

# =============================================================================
# AWS ECR Repositories Outputs
# =============================================================================

output "ecr_repository_backend_url" {
  description = "URL of the DuckStore Backend ECR repository."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_frontend_url" {
  description = "URL of the DuckStore Frontend ECR repository."
  value       = aws_ecr_repository.frontend.repository_url
}

# =============================================================================
# Amazon EKS Cluster Outputs
# =============================================================================

output "eks_cluster_name" {
  description = "Name of the provisioned EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server endpoint for the EKS cluster."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_arn" {
  description = "ARN of the provisioned EKS cluster."
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "ARN of the IAM OIDC Provider for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "update_kubeconfig_command" {
  description = "CLI command to configure kubectl credentials for the EKS cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}
