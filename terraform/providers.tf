terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # ===========================================================================
  # Remote State Management Template
  # ===========================================================================
  # WARNING: Local state files (terraform.tfstate) should NEVER be used in
  # team environments or automated CI/CD pipelines. Local state creates risks
  # of race conditions, simultaneous applies, and state loss or corruption.
  #
  # To enable remote state storage with atomic state locking:
  # 1. Provision an S3 bucket (with versioning and default encryption enabled).
  # 2. For Terraform >= 1.10: Enable native S3 locking with `use_lockfile = true`.
  # 3. For Terraform < 1.10: Provision a DynamoDB table with partition key `LockID` (String).
  #
  # backend "s3" {
  #   bucket         = "your-company-terraform-state"
  #   key            = "duckstore/production/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   use_lockfile   = true                   # S3 native locking (Terraform >= 1.10)
  #   # dynamodb_table = "terraform-locks"     # DynamoDB locking (Terraform < 1.10)
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
