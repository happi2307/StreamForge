data "aws_region" "current" {}

locals {
  asset_content_types = {
    "index.html" = "text/html"
    "styles.css" = "text/css"
    "app.js"     = "application/javascript"
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.project_name}-${var.environment}-dashboard-oac"
  description                       = "CloudFront access for the private StreamForge dashboard bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${var.project_name}-${var.environment}-dashboard-security"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; connect-src 'self' https:; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
      override                = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} ${var.environment} dashboard"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "private-dashboard-bucket"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "private-dashboard-bucket"
    viewer_protocol_policy     = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    compress                   = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  tags = var.tags
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

resource "aws_s3_object" "assets" {
  for_each = local.asset_content_types

  bucket                 = aws_s3_bucket.this.id
  key                    = each.key
  source                 = "${var.asset_source_directory}/${each.key}"
  source_hash            = filemd5("${var.asset_source_directory}/${each.key}")
  content_type           = each.value
  cache_control          = "no-cache, no-store, must-revalidate"
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
}

resource "aws_s3_object" "runtime_config" {
  bucket                 = aws_s3_bucket.this.id
  key                    = "config.js"
  content_type           = "application/javascript"
  cache_control          = "no-cache, no-store, must-revalidate"
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  content = templatefile("${var.asset_source_directory}/config.template.js", {
    api_endpoint   = trimsuffix(var.api_endpoint, "/")
    cognito_domain = "https://${var.cognito_domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    client_id      = var.cognito_client_id
    redirect_uri   = "https://${aws_cloudfront_distribution.this.domain_name}"
  })
}
