output "bucket_name" {
  description = "Name of the central S3 server access-log destination bucket."
  value       = aws_s3_bucket.this.bucket
}
