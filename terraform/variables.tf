# =============================================================================
# General & Project Configuration
# =============================================================================

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "duckstore"
}

variable "environment" {
  description = "Environment name (dev/staging/prod). Used in names and tags."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner tag applied to all resources."
  type        = string
  default     = "Mohamed Elwishy"
}

variable "domain_name" {
  description = "Domain name for DNS configuration and ingress host."
  type        = string
  default     = ""
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (spread across 2 AZs)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnet CIDRs are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (spread across 2 AZs)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs are required for EKS worker nodes."
  }
}

# =============================================================================
# Amazon EKS Configuration
# =============================================================================

variable "eks_version" {
  description = "Kubernetes control plane version for Amazon EKS."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Instance types for the EKS Managed Node Group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes in the Managed Node Group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes in the Managed Node Group."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes in the Managed Node Group."
  type        = number
  default     = 4
}

# =============================================================================
# Locals
# =============================================================================

locals {
  name         = "${var.project_name}-${var.environment}"
  cluster_name = "${local.name}-eks"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
