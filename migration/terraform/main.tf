# =====================================================
# StreamForge Phase 6 - Shared Terraform Configuration
# Provider, locals, and account/region data sources
# =====================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      Phase       = "phase6-migration"
      ManagedBy   = "terraform"
    }
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
