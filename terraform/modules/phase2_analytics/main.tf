locals {
  normalized_clean_bucket_prefix = trim(var.clean_bucket_prefix, "/")
  canonical_table_location       = local.normalized_clean_bucket_prefix == "" ? format("s3://%s/", var.clean_bucket_name) : format("s3://%s/%s/", var.clean_bucket_name, local.normalized_clean_bucket_prefix)

  normalized_athena_results_prefix = trim(var.athena_results_prefix, "/")
  athena_output_location = format(
    "s3://%s/%s/",
    var.athena_results_bucket_name,
    local.normalized_athena_results_prefix,
  )
}

data "aws_iam_policy_document" "crawler_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "crawler_data_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      var.clean_bucket_arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${var.clean_bucket_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [
      var.kms_key_arn,
    ]
  }
}

resource "aws_iam_role" "crawler" {
  name               = var.glue_crawler_role_name
  assume_role_policy = data.aws_iam_policy_document.crawler_assume_role.json
  tags = merge(var.tags, {
    Name    = var.glue_crawler_role_name
    Service = "phase2-analytics"
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "crawler_data_access" {
  name   = var.glue_crawler_inline_policy_name
  role   = aws_iam_role.crawler.id
  policy = data.aws_iam_policy_document.crawler_data_access.json
}

resource "aws_glue_catalog_database" "this" {
  name        = var.glue_database_name
  description = var.glue_database_description

  create_table_default_permission {
    permissions = ["ALL"]

    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }
}

resource "aws_glue_crawler" "this" {
  name          = var.glue_crawler_name
  description   = var.glue_crawler_description
  database_name = aws_glue_catalog_database.this.name
  role          = aws_iam_role.crawler.name

  s3_target {
    path       = format("s3://%s/", var.clean_bucket_name)
    exclusions = var.crawler_exclusions
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  lineage_configuration {
    crawler_lineage_settings = "DISABLE"
  }

  tags = merge(var.tags, {
    Name    = var.glue_crawler_name
    Service = "phase2-analytics"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy.crawler_data_access,
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
    Service = "phase2-analytics"
  })
}

resource "aws_glue_catalog_table" "canonical_customers" {
  name          = var.canonical_table_name
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                 = "TRUE"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location          = local.canonical_table_location
    input_format      = "org.apache.hadoop.mapred.TextInputFormat"
    output_format     = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    number_of_buckets = -1

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"

      parameters = {
        "serialization.format" = "1"
        "field.delim"          = ","
      }
    }

    columns {
      name = "customer_id"
      type = "bigint"
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

    skewed_info {
      skewed_column_names               = []
      skewed_column_values              = []
      skewed_column_value_location_maps = {}
    }
  }

  lifecycle {
    ignore_changes = [
      owner,
      parameters["transient_lastDdlTime"],
    ]
  }
}
