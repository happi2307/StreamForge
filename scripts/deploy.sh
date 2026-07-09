#!/usr/bin/env bash
# Deploy the StreamForge Phase 1 pipeline to AWS.
#
# Prerequisites: awscli v2 configured (`aws configure`), permission to create
# S3 buckets, IAM roles, Lambda functions, and EventBridge rules.
#
# Usage:
#   RAW=my-raw CLEAN=my-clean REJECTED=my-rejected REGION=us-east-1 \
#     bash scripts/deploy.sh
#
# Bucket names must be globally unique. Defaults below are placeholders.
set -euo pipefail

REGION="${REGION:-us-east-1}"
RAW="${RAW:-dataflow-raw}"
CLEAN="${CLEAN:-dataflow-clean}"
REJECTED="${REJECTED:-dataflow-rejected}"
FUNC="${FUNC:-streamforge-processor}"
ROLE="${ROLE:-streamforge-lambda-role}"
RULE="${RULE:-streamforge-raw-uploads}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo ">> Account $ACCOUNT_ID / region $REGION"

# --- 1. Buckets -------------------------------------------------------------
for b in "$RAW" "$CLEAN" "$REJECTED"; do
  if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
    echo ">> Bucket $b already exists"
  elif [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$b" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$b" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
done

# Raw bucket must emit events to EventBridge.
aws s3api put-bucket-notification-configuration --bucket "$RAW" \
  --notification-configuration '{"EventBridgeConfiguration":{}}'

# --- 2. Package -------------------------------------------------------------
rm -rf build function.zip
pip install -r lambda/requirements.txt -t build/ >/dev/null
cp lambda/handler.py lambda/validator.py build/
( cd build && zip -qr ../function.zip . )
echo ">> Built function.zip"

# --- 3. IAM role ------------------------------------------------------------
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document "$TRUST"
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
fi
POLICY=$(cat <<JSON
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::$RAW/*"},
  {"Effect":"Allow","Action":"s3:PutObject","Resource":["arn:aws:s3:::$CLEAN/*","arn:aws:s3:::$REJECTED/*"]}
]}
JSON
)
aws iam put-role-policy --role-name "$ROLE" --policy-name streamforge-s3 \
  --policy-document "$POLICY"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE}"
echo ">> Role $ROLE_ARN ready (waiting for propagation)"
sleep 10

# --- 4. Lambda --------------------------------------------------------------
ENV="Variables={CLEAN_BUCKET=$CLEAN,REJECTED_BUCKET=$REJECTED}"
if aws lambda get-function --function-name "$FUNC" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNC" \
    --zip-file fileb://function.zip >/dev/null
  aws lambda update-function-configuration --function-name "$FUNC" \
    --environment "$ENV" >/dev/null
else
  aws lambda create-function --function-name "$FUNC" \
    --runtime python3.12 --handler handler.lambda_handler \
    --role "$ROLE_ARN" --zip-file fileb://function.zip \
    --timeout 60 --memory-size 256 --environment "$ENV" >/dev/null
fi
FUNC_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNC}"
echo ">> Lambda $FUNC_ARN deployed"

# --- 5. EventBridge ---------------------------------------------------------
aws events put-rule --name "$RULE" --region "$REGION" \
  --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"],\"detail\":{\"bucket\":{\"name\":[\"$RAW\"]}}}" >/dev/null

aws lambda add-permission --function-name "$FUNC" \
  --statement-id eventbridge-invoke --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "arn:aws:events:${REGION}:${ACCOUNT_ID}:rule/${RULE}" >/dev/null 2>&1 || true

aws events put-targets --rule "$RULE" --region "$REGION" \
  --targets "Id=1,Arn=$FUNC_ARN" >/dev/null
echo ">> EventBridge rule $RULE -> $FUNC wired"

echo
echo "Done. Upload a CSV to test:"
echo "  aws s3 cp sample_data/customers.csv s3://$RAW/customers.csv"
echo "  aws s3 ls s3://$CLEAN/ && aws s3 ls s3://$REJECTED/"
