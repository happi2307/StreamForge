data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
    CreatedBy   = var.created_by
    Repository  = var.repository
  }

  bucket_service_labels = {
    raw            = "raw"
    clean          = "clean"
    rejected       = "rejected"
    metadata       = "metadata"
    curated        = "curated"
    quarantine     = "quarantine"
    athena_results = "athena-results"
  }

  default_bucket_names = {
    for key, label in local.bucket_service_labels :
    key => format(
      "%s-%s-%s-%s-%s",
      var.project_name,
      var.environment,
      label,
      data.aws_caller_identity.current.account_id,
      data.aws_region.current.name,
    )
  }

  bucket_names = merge(local.default_bucket_names, var.bucket_name_overrides)

  default_current_version_expiration_days = {
    raw            = null
    clean          = null
    rejected       = null
    metadata       = null
    curated        = null
    quarantine     = 180
    athena_results = 30
  }

  current_version_expiration_days = merge(
    local.default_current_version_expiration_days,
    var.bucket_current_version_expiration_days_overrides,
  )

  default_noncurrent_version_expiration_days = {
    raw            = 180
    clean          = 180
    rejected       = 180
    metadata       = 180
    curated        = 180
    quarantine     = 180
    athena_results = 30
  }

  noncurrent_version_expiration_days = merge(
    local.default_noncurrent_version_expiration_days,
    var.bucket_noncurrent_version_expiration_days_overrides,
  )
}

module "kms" {
  source      = "../../modules/kms"
  alias_name  = var.kms_alias_name
  description = var.kms_description
  tags        = merge(local.common_tags, { Name = var.kms_alias_name })
}

module "buckets" {
  source   = "../../modules/s3"
  for_each = local.bucket_names

  bucket_name                        = each.value
  kms_key_arn                        = module.kms.key_arn
  current_version_expiration_days    = local.current_version_expiration_days[each.key]
  noncurrent_version_expiration_days = local.noncurrent_version_expiration_days[each.key]
  tags = merge(local.common_tags, {
    Name    = each.value
    Service = each.key
  })
}
