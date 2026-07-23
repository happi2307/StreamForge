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

module "phase1_runtime" {
  source = "../../modules/phase1_runtime"

  project_name              = var.project_name
  environment               = var.environment
  lambda_function_name      = var.lambda_function_name
  lambda_description        = var.lambda_description
  lambda_role_name          = var.lambda_role_name
  lambda_inline_policy_name = var.lambda_inline_policy_name
  event_rule_name           = var.event_rule_name
  event_rule_description    = var.event_rule_description
  event_target_id           = var.event_target_id
  lambda_package_path       = var.lambda_package_path
  lambda_handler            = var.lambda_handler
  lambda_runtime            = var.lambda_runtime
  lambda_timeout            = var.lambda_timeout
  lambda_memory_size        = var.lambda_memory_size
  raw_bucket_name           = module.buckets["raw"].bucket_name
  raw_bucket_arn            = module.buckets["raw"].bucket_arn
  raw_bucket_id             = module.buckets["raw"].bucket_id
  clean_bucket_name         = module.buckets["clean"].bucket_name
  clean_bucket_arn          = module.buckets["clean"].bucket_arn
  rejected_bucket_name      = module.buckets["rejected"].bucket_name
  rejected_bucket_arn       = module.buckets["rejected"].bucket_arn
  metadata_bucket_name      = module.buckets["metadata"].bucket_name
  metadata_bucket_arn       = module.buckets["metadata"].bucket_arn
  metadata_prefix           = var.metadata_prefix
  phase1_pipeline_version   = var.phase1_pipeline_version
  kms_key_arn               = module.kms.key_arn
  tags = merge(local.common_tags, {
    Name    = var.lambda_function_name
    Service = "phase1-runtime"
  })
}

module "phase2_analytics" {
  source = "../../modules/phase2_analytics"

  project_name                    = var.project_name
  environment                     = var.environment
  glue_database_name              = var.glue_database_name
  glue_database_description       = var.glue_database_description
  glue_crawler_role_name          = var.glue_crawler_role_name
  glue_crawler_inline_policy_name = var.glue_crawler_inline_policy_name
  glue_crawler_name               = var.glue_crawler_name
  glue_crawler_description        = var.glue_crawler_description
  crawler_exclusions              = var.crawler_exclusions
  athena_workgroup_name           = var.athena_workgroup_name
  athena_workgroup_description    = var.athena_workgroup_description
  athena_results_bucket_name      = module.buckets["athena_results"].bucket_name
  athena_results_prefix           = var.athena_results_prefix
  clean_bucket_name               = module.buckets["clean"].bucket_name
  clean_bucket_arn                = module.buckets["clean"].bucket_arn
  clean_bucket_prefix             = var.clean_bucket_prefix
  canonical_table_name            = var.phase2_canonical_table_name
  kms_key_arn                     = module.kms.key_arn
  tags                            = local.common_tags
}

module "phase3_curated" {
  source = "../../modules/phase3_curated"

  project_name                 = var.project_name
  environment                  = var.environment
  glue_database_name           = var.glue_database_name
  glue_job_role_name           = var.phase3_glue_job_role_name
  glue_job_inline_policy_name  = var.phase3_glue_job_inline_policy_name
  glue_job_name                = var.phase3_glue_job_name
  glue_job_description         = var.phase3_glue_job_description
  glue_job_script_location     = replace(var.phase3_glue_job_script_location, "ACCOUNTID", data.aws_caller_identity.current.account_id)
  glue_job_extra_py_files      = replace(var.phase3_glue_job_extra_py_files, "ACCOUNTID", data.aws_caller_identity.current.account_id)
  athena_workgroup_name        = var.phase3_athena_workgroup_name
  athena_workgroup_description = var.phase3_athena_workgroup_description
  athena_results_bucket_name   = module.buckets["athena_results"].bucket_name
  curated_table_name           = var.phase3_curated_table_name
  curated_table_location       = format("s3://%s/%s", module.buckets["curated"].bucket_name, var.phase3_curated_prefix)
  clean_bucket_name            = module.buckets["clean"].bucket_name
  clean_bucket_arn             = module.buckets["clean"].bucket_arn
  metadata_bucket_name         = module.buckets["metadata"].bucket_name
  metadata_bucket_arn          = module.buckets["metadata"].bucket_arn
  curated_bucket_name          = module.buckets["curated"].bucket_name
  curated_bucket_arn           = module.buckets["curated"].bucket_arn
  quarantine_bucket_name       = module.buckets["quarantine"].bucket_name
  quarantine_bucket_arn        = module.buckets["quarantine"].bucket_arn
  kms_key_arn                  = module.kms.key_arn
  metadata_prefix              = var.metadata_prefix
  curated_prefix               = var.phase3_curated_prefix
  pipeline_version             = var.phase3_pipeline_version
  max_invalid_percent          = var.phase3_max_invalid_percent
  tags                         = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name                 = var.project_name
  environment                  = var.environment
  sns_topic_name               = var.alerts_sns_topic_name
  sns_topic_display_name       = var.alerts_sns_topic_display_name
  notification_email           = var.alerts_notification_email
  sns_kms_master_key_id        = var.alerts_sns_kms_master_key_id
  lambda_function_name         = module.phase1_runtime.lambda_function_name
  lambda_error_threshold       = var.lambda_error_threshold
  lambda_throttle_threshold    = var.lambda_throttle_threshold
  lambda_duration_threshold_ms = var.lambda_duration_threshold_ms
  alarm_period_seconds         = var.alarm_period_seconds
  alarm_evaluation_periods     = var.alarm_evaluation_periods
  glue_job_name                = module.phase3_curated.glue_job_name
  glue_failure_rule_name       = var.glue_failure_rule_name
  glue_failure_states          = var.glue_failure_states
  tags = merge(local.common_tags, {
    Service = "monitoring"
  })
}
