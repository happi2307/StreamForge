# KMS access issues

## Symptoms

S3, Lambda, Glue, SNS, SQS, or CloudWatch Logs report `AccessDenied`,
`KMSAccessDeniedException`, or an encryption failure.

## Investigate

1. Identify the caller, KMS key ARN, service, and source resource from the error.
2. Confirm the StreamForge KMS alias resolves to the Terraform-managed key.
3. Check the caller's IAM policy and the key policy together; both must allow the operation.
4. For SNS, SQS, EventBridge, and CloudWatch Logs, confirm the relevant service principal remains in the Terraform KMS policy.

## Recover

Make the least-privilege policy change in Terraform, run `terraform plan`, and
apply through the approved workflow. Do not weaken the key policy with wildcard
principals or disable encryption to restore service.
