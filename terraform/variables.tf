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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet the node lives in."
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the K3s node."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access."
  type        = string
  default     = ""
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach port 22."
  type        = list(string)
  default     = []
}

variable "k8s_api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API on port 6443."
  type        = list(string)
  default     = []
}

variable "enable_nodeport_range" {
  description = "Open the NodePort range 30000-32767 to the internet."
  type        = bool
  default     = false
}

variable "k3s_version" {
  description = "K3s release channel or exact version."
  type        = string
  default     = "stable"
}

variable "disable_metrics_server" {
  description = "Skip K3s bundled metrics-server to conserve memory."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for DNS configuration and TLS SAN."
  type        = string
  default     = ""
}

locals {
  name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
