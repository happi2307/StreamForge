# Lambda failures

## Trigger

The `streamforge-dev-lambda-errors` alarm enters `ALARM` after a Phase 1
invocation reports an error.

## Investigate

1. Open the `streamforge-dev-pipeline` dashboard and identify the affected time window.
2. Inspect `/aws/lambda/streamforge-processor` CloudWatch logs for the request ID and source S3 key.
3. Confirm the raw object still exists and that the Lambda role can read it and write to the clean, rejected, and metadata buckets.
4. Check KMS permissions if the logs contain `AccessDenied` or `KMS` errors.

## Recover

Correct the input, permission, or code issue, then re-upload the source object
with a new key or version. Do not manually copy data directly into clean or
rejected buckets: Phase 1 must produce the processing manifest.

## Escalate

If errors persist across valid inputs, disable further manual uploads and open
an incident with the log request IDs and affected source keys.
