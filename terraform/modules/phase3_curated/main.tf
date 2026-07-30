locals {
  normalized_athena_results_prefix = trim(var.athena_results_prefix, "/")
  athena_output_location           = format("s3://%s/%s/", var.athena_results_bucket_name, local.normalized_athena_results_prefix)
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "job_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "job_data_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      var.clean_bucket_arn,
      var.metadata_bucket_arn,
      var.curated_bucket_arn,
      var.quarantine_bucket_arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${var.clean_bucket_arn}/*",
      "${var.metadata_bucket_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${var.curated_bucket_arn}/*",
      "${var.quarantine_bucket_arn}/*",
      "${var.metadata_bucket_arn}/serving/batches/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [
      var.kms_key_arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.pipeline_metric_namespace]
    }
  }

  # Glue associates the configured KMS key with its continuous-log groups at
  # job startup. Scope the permission to this job's security-configuration and
  # role-specific log-group namespace rather than granting account-wide access.
  statement {
    effect = "Allow"
    actions = [
      "logs:AssociateKmsKey",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${var.glue_job_name}-security-role/${var.glue_job_role_name}/*",
    ]
  }
}

resource "aws_iam_role" "job" {
  name               = var.glue_job_role_name
  assume_role_policy = data.aws_iam_policy_document.job_assume_role.json
  tags = merge(var.tags, {
    Name    = var.glue_job_role_name
    Service = "phase3-curated"
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "job_data_access" {
  name   = var.glue_job_inline_policy_name
  role   = aws_iam_role.job.id
  policy = data.aws_iam_policy_document.job_data_access.json
}

resource "aws_glue_security_configuration" "this" {
  name = "${var.glue_job_name}-security"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.kms_key_arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }
  }
}

resource "aws_glue_job" "this" {
  #checkov:skip=CKV_AWS_195: The job explicitly references aws_glue_security_configuration.this; this static check does not resolve the Terraform reference.
  name                   = var.glue_job_name
  description            = var.glue_job_description
  role_arn               = aws_iam_role.job.arn
  glue_version           = var.glue_job_glue_version
  timeout                = var.glue_job_timeout
  worker_type            = var.glue_job_worker_type
  number_of_workers      = var.glue_job_number_of_workers
  security_configuration = aws_glue_security_configuration.this.name

  execution_property {
    max_concurrent_runs = var.glue_job_max_concurrent_runs
  }

  command {
    name            = "glueetl"
    script_location = var.glue_job_script_location
    python_version  = "3"
  }

  default_arguments = {
    "--CURATED_TABLE"                    = var.curated_table_name
    "--CURATED_BUCKET"                   = var.curated_bucket_name
    "--PIPELINE_VERSION"                 = var.pipeline_version
    "--enable-metrics"                   = "true"
    "--extra-py-files"                   = var.glue_job_extra_py_files
    "--MAX_INVALID_PERCENT"              = var.max_invalid_percent
    "--CURATED_PREFIX"                   = var.curated_prefix
    "--QUARANTINE_BUCKET"                = var.quarantine_bucket_name
    "--DATABASE_NAME"                    = var.glue_database_name
    "--ENVIRONMENT"                      = var.environment
    "--enable-continuous-cloudwatch-log" = "true"
    "--METADATA_BUCKET"                  = var.metadata_bucket_name
    "--INPUT_BUCKET"                     = var.clean_bucket_name
    "--job-language"                     = "python"
    "--METADATA_PREFIX"                  = var.metadata_prefix
    "--METRICS_NAMESPACE"                = var.pipeline_metric_namespace
  }

  tags = merge(var.tags, {
    Name    = var.glue_job_name
    Service = "phase3-curated"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy.job_data_access,
  ]
}

resource "aws_athena_workgroup" "this" {
  name        = var.athena_workgroup_name
  description = var.athena_workgroup_description
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "AUTO"
    }

    result_configuration {
      output_location = local.athena_output_location

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }

  tags = merge(var.tags, {
    Name    = var.athena_workgroup_name
    Service = "phase3-curated"
  })
}

resource "aws_glue_catalog_table" "curated" {
  name          = var.curated_table_name
  database_name = var.glue_database_name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location          = var.curated_table_location
    input_format      = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format     = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed        = false
    number_of_buckets = -1

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "customer_id"
      type = "string"
    }

    columns {
      name = "name"
      type = "string"
    }

    columns {
      name = "email"
      type = "string"
    }

    columns {
      name = "sales"
      type = "bigint"
    }

    columns {
      name = "sales_category"
      type = "string"
    }

    columns {
      name = "ingestion_timestamp"
      type = "string"
    }

    columns {
      name = "processed_timestamp"
      type = "string"
    }

    columns {
      name = "phase1_batch_id"
      type = "string"
    }

    columns {
      name = "phase3_batch_id"
      type = "string"
    }

    columns {
      name = "source_filename"
      type = "string"
    }

    columns {
      name = "source_raw_key"
      type = "string"
    }

    columns {
      name = "source_clean_key"
      type = "string"
    }

    columns {
      name = "pipeline_version"
      type = "string"
    }

    skewed_info {
      skewed_column_names               = []
      skewed_column_values              = []
      skewed_column_value_location_maps = {}
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  lifecycle {
    ignore_changes = [
      owner,
      parameters["transient_lastDdlTime"],
    ]
  }
}
