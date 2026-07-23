data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  backend_bucket_name = var.backend_bucket_name != "" ? var.backend_bucket_name : format(
    "%s-%s-tfstate-%s-%s",
    var.project_name,
    var.environment,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

  backend_access_logs_bucket_name = format(
    "%s-%s-tfstate-access-logs-%s-%s",
    var.project_name,
    var.environment,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

  lock_table_name = var.lock_table_name != "" ? var.lock_table_name : format(
    "%s-%s-terraform-locks",
    var.project_name,
    var.environment,
  )

  kms_alias_name = var.kms_alias_name != "" ? var.kms_alias_name : format(
    "alias/%s-%s-tfstate",
    var.project_name,
    var.environment,
  )

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
    CreatedBy   = var.created_by
    Repository  = var.repository
  }
}

module "kms" {
  source      = "../../modules/kms"
  alias_name  = local.kms_alias_name
  description = "KMS key for StreamForge Terraform backend state."
  tags        = merge(local.common_tags, { Name = local.kms_alias_name })
}

module "state_bucket" {
  source = "../../modules/s3"

  bucket_name                        = local.backend_bucket_name
  kms_key_arn                        = module.kms.key_arn
  access_log_bucket_name             = module.access_logs.bucket_name
  current_version_expiration_days    = null
  noncurrent_version_expiration_days = 180
  tags = merge(local.common_tags, {
    Name    = local.backend_bucket_name
    Service = "terraform-state"
  })
}

module "access_logs" {
  source = "../../modules/s3_access_logs"

  bucket_name = local.backend_access_logs_bucket_name
  tags        = merge(local.common_tags, { Service = "terraform-state-access-logs" })
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = module.kms.key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name    = local.lock_table_name
    Service = "terraform-locks"
  })
}
