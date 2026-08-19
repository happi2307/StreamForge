data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "terraform_state" {
  name = var.terraform_state_kms_alias
}

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

  dashboard_static_bucket_name = format(
    "%s-%s-dashboard-%s-%s",
    var.project_name,
    var.environment,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

  s3_access_logs_bucket_name = format(
    "%s-%s-s3-access-logs-%s-%s",
    var.project_name,
    var.environment,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

  terraform_state_bucket_name = format(
    "%s-shared-tfstate-%s-%s",
    var.project_name,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.name,
  )

  terraform_lock_table_name = format(
    "%s-shared-terraform-locks",
    var.project_name,
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
    {
      sid         = "AllowRdsUse"
      principals  = ["rds.amazonaws.com"]
      via_service = "rds.${data.aws_region.current.name}.amazonaws.com"
    },
    {
      sid         = "AllowSecretsManagerUse"
      principals  = ["secretsmanager.amazonaws.com"]
      via_service = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
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
    {
      sid        = "AllowCloudFrontDashboardRead"
      principals = ["cloudfront.amazonaws.com"]
    },
    {
      sid        = "AllowCloudFrontLogDelivery"
      principals = ["delivery.logs.amazonaws.com"]
    },
  ]
  cloudwatch_logs_encryption_context_arns = [
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_name}",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.dashboard_lambda_function_name}",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.project_name}-${var.environment}-dashboard-api",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:aws-waf-logs-${var.project_name}-${var.environment}-dashboard",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${var.phase3_glue_job_name}-security-role/${var.phase3_glue_job_role_name}/error",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${var.phase3_glue_job_name}-security-role/${var.phase3_glue_job_role_name}/output",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.phase5_loader_function_name}",
  ]
  tags = merge(local.common_tags, { Name = var.kms_alias_name })
}

module "web_static" {
  source = "../../modules/web_static"

  project_name           = var.project_name
  environment            = var.environment
  bucket_name            = local.dashboard_static_bucket_name
  kms_key_arn            = module.kms.key_arn
  access_log_bucket_name = module.s3_access_logs.bucket_name
  asset_source_directory = abspath("${path.module}/../../../web")
  api_endpoint           = module.web_console.api_endpoint
  cognito_domain         = module.web_console.cognito_domain
  cognito_client_id      = module.web_console.user_pool_client_id
  tags                   = merge(local.common_tags, { Service = "dashboard-static" })
}

module "s3_access_logs" {
  source = "../../modules/s3_access_logs"

  bucket_name = local.s3_access_logs_bucket_name
  tags        = merge(local.common_tags, { Service = "s3-access-logs" })
}

module "buckets" {
  source   = "../../modules/s3"
  for_each = local.bucket_names

  bucket_name                        = each.value
  kms_key_arn                        = module.kms.key_arn
  access_log_bucket_name             = module.s3_access_logs.bucket_name
  current_version_expiration_days    = local.current_version_expiration_days[each.key]
  noncurrent_version_expiration_days = local.noncurrent_version_expiration_days[each.key]
  cors_rules = each.key == "raw" ? [{
    allowed_headers = ["Content-Type"]
    allowed_methods = ["PUT"]
    allowed_origins = concat(var.dashboard_allowed_origins, [module.web_static.dashboard_origin])
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }] : []
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

module "phase5_serving" {
  source = "../../modules/phase5_serving"

  name_prefix               = "${var.project_name}-${var.environment}"
  environment               = var.environment
  kms_key_arn               = module.kms.key_arn
  vpc_cidr                  = var.phase5_vpc_cidr
  subnet_cidrs              = var.phase5_subnet_cidrs
  db_name                   = var.phase5_db_name
  db_schema                 = var.phase5_db_schema
  serverless_min_acu        = var.phase5_serverless_min_acu
  serverless_max_acu        = var.phase5_serverless_max_acu
  curated_bucket_name       = module.buckets["curated"].bucket_name
  curated_bucket_arn        = module.buckets["curated"].bucket_arn
  curated_bucket_id         = module.buckets["curated"].bucket_id
  metadata_bucket_name      = module.buckets["metadata"].bucket_name
  metadata_bucket_arn       = module.buckets["metadata"].bucket_arn
  alert_topic_arn           = module.phase4_operations.alert_topic_arn
  pipeline_metric_namespace = var.pipeline_metric_namespace
  pipeline_version          = var.phase5_pipeline_version
  loader_function_name      = var.phase5_loader_function_name
  loader_role_name          = var.phase5_loader_role_name
  loader_inline_policy_name = var.phase5_loader_inline_policy_name
  loader_package_path       = var.phase5_loader_package_path
  event_rule_name           = var.phase5_event_rule_name
  tags = merge(local.common_tags, {
    Service = "phase5-serving"
  })
}

module "web_console" {
  source = "../../modules/web_console"

  project_name         = var.project_name
  environment          = var.environment
  lambda_function_name = var.dashboard_lambda_function_name
  lambda_package_path  = var.dashboard_lambda_package_path
  raw_bucket_name      = module.buckets["raw"].bucket_name
  raw_bucket_arn       = module.buckets["raw"].bucket_arn
  metadata_bucket_name = module.buckets["metadata"].bucket_name
  metadata_bucket_arn  = module.buckets["metadata"].bucket_arn
  clean_bucket_arn     = module.buckets["clean"].bucket_arn
  rejected_bucket_arn  = module.buckets["rejected"].bucket_arn
  metadata_prefix      = var.metadata_prefix
  kms_key_arn          = module.kms.key_arn
  allowed_origins      = concat(var.dashboard_allowed_origins, [module.web_static.dashboard_origin])
  tags                 = merge(local.common_tags, { Service = "web-console" })
}

module "github_actions_oidc" {
  source = "../../modules/github_actions_oidc"

  project_name        = var.project_name
  environment         = var.environment
  github_repository   = var.github_repository
  github_environment  = var.github_environment
  role_name           = var.github_actions_role_name
  state_bucket_name   = local.terraform_state_bucket_name
  state_kms_key_arn   = data.aws_kms_alias.terraform_state.target_key_arn
  lock_table_arn      = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${local.terraform_lock_table_name}"
  project_kms_key_arn = module.kms.key_arn
  project_bucket_arns = concat(
    [for bucket in module.buckets : bucket.bucket_arn],
    [
      "arn:aws:s3:::${module.s3_access_logs.bucket_name}",
      "arn:aws:s3:::${module.web_static.bucket_name}",
      "arn:aws:s3:::${module.web_static.access_log_bucket_name}",
    ],
  )
  worker_role_names = [
    var.lambda_role_name,
    var.dashboard_lambda_function_name == "" ? "" : "${var.dashboard_lambda_function_name}-role",
    var.glue_crawler_role_name,
    var.phase3_glue_job_role_name,
    var.phase5_loader_role_name,
  ]
  tags = merge(local.common_tags, { Service = "github-actions-oidc" })
}
