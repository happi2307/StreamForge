variable "bucket_name" {
  description = "Name of the central S3 server access-log destination bucket."
  type        = string
}

variable "tags" {
  description = "Tags applied to the log bucket."
  type        = map(string)
  default     = {}
}
