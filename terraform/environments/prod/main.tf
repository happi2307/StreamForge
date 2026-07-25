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

  s3_access_logs_bucket_name = format(
    "%s-%s-s3-access-logs-%s-%s",
    var.project_name,
    var.environment,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

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
  service_key_access = [
    {
      sid         = "AllowSnsUse"
      principals  = ["sns.amazonaws.com"]
      via_service = "sns.${data.aws_region.current.name}.amazonaws.com"
    },
    {
      sid         = "AllowSqsUse"
      principals  = ["sqs.amazonaws.com"]
      via_service = "sqs.${data.aws_region.current.name}.amazonaws.com"
    },
  ]
  direct_service_key_access = [
    {
      sid        = "AllowCloudWatchAlarmPublishing"
      principals = ["cloudwatch.amazonaws.com"]
    },
    {
      sid        = "AllowEventBridgePublishing"
      principals = ["events.amazonaws.com"]
    },
  ]
  cloudwatch_logs_encryption_context_arns = [
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_name}",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${var.phase3_glue_job_name}-security-role/${var.phase3_glue_job_role_name}/error",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${var.phase3_glue_job_name}-security-role/${var.phase3_glue_job_role_name}/output",
  ]
  tags = merge(local.common_tags, { Name = var.kms_alias_name })
}

module "buckets" {
  source   = "../../modules/s3"
  for_each = local.bucket_names

  bucket_name                        = each.value
  kms_key_arn                        = module.kms.key_arn
  access_log_bucket_name             = module.s3_access_logs.bucket_name
  current_version_expiration_days    = local.current_version_expiration_days[each.key]
  noncurrent_version_expiration_days = local.noncurrent_version_expiration_days[each.key]
  tags = merge(local.common_tags, {
    Name    = each.value
    Service = each.key
  })
}

module "phase1_runtime" {
  source = "../../modules/phase1_runtime"

  depends_on = [module.phase4_operations]

  project_name                             = var.project_name
  environment                              = var.environment
  lambda_function_name                     = var.lambda_function_name
  lambda_description                       = var.lambda_description
  lambda_role_name                         = var.lambda_role_name
  lambda_inline_policy_name                = var.lambda_inline_policy_name
  event_rule_name                          = var.event_rule_name
  event_rule_description                   = var.event_rule_description
  event_target_id                          = var.event_target_id
  lambda_package_path                      = var.lambda_package_path
  lambda_handler                           = var.lambda_handler
  lambda_runtime                           = var.lambda_runtime
  lambda_timeout                           = var.lambda_timeout
  lambda_memory_size                       = var.lambda_memory_size
  lambda_log_retention_days                = var.lambda_log_retention_days
  eventbridge_dead_letter_queue_arn        = module.phase4_operations.eventbridge_dead_letter_queue_arn
  eventbridge_maximum_event_age_in_seconds = var.eventbridge_maximum_event_age_in_seconds
  eventbridge_maximum_retry_attempts       = var.eventbridge_maximum_retry_attempts
  raw_bucket_name                          = module.buckets["raw"].bucket_name
  raw_bucket_arn                           = module.buckets["raw"].bucket_arn
  raw_bucket_id                            = module.buckets["raw"].bucket_id
  clean_bucket_name                        = module.buckets["clean"].bucket_name
  clean_bucket_arn                         = module.buckets["clean"].bucket_arn
  rejected_bucket_name                     = module.buckets["rejected"].bucket_name
  rejected_bucket_arn                      = module.buckets["rejected"].bucket_arn
  metadata_bucket_name                     = module.buckets["metadata"].bucket_name
  metadata_bucket_arn                      = module.buckets["metadata"].bucket_arn
  metadata_prefix                          = var.metadata_prefix
  phase1_pipeline_version                  = var.phase1_pipeline_version
  kms_key_arn                              = module.kms.key_arn
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
  pipeline_metric_namespace    = var.pipeline_metric_namespace
  tags                         = local.common_tags
}

module "s3_access_logs" {
  source = "../../modules/s3_access_logs"

  bucket_name = local.s3_access_logs_bucket_name
  tags        = merge(local.common_tags, { Service = "s3-access-logs" })
}

module "phase4_operations" {
  source = "../../modules/phase4_operations"

  name_prefix                               = "${var.project_name}-${var.environment}"
  environment                               = var.environment
  kms_key_arn                               = module.kms.key_arn
  alert_topic_name                          = var.operations_alert_topic_name
  alert_topic_display_name                  = var.operations_alert_topic_display_name
  alert_email                               = var.operations_alert_email
  eventbridge_dlq_name                      = var.eventbridge_dlq_name
  eventbridge_dlq_message_retention_seconds = var.eventbridge_dlq_message_retention_seconds
  event_rule_name                           = var.event_rule_name
  lambda_function_name                      = var.lambda_function_name
  glue_job_name                             = var.phase3_glue_job_name
  phase2_athena_workgroup_name              = var.athena_workgroup_name
  phase3_athena_workgroup_name              = var.phase3_athena_workgroup_name
  pipeline_metric_namespace                 = var.pipeline_metric_namespace
  max_invalid_percent                       = tonumber(var.phase3_max_invalid_percent)
  alarm_period_seconds                      = var.operations_alarm_period_seconds
  tags = merge(local.common_tags, {
    Service = "phase4-operations"
  })
}
