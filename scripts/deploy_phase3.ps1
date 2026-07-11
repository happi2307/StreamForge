param(
    [string]$Region = "us-east-1",
    [string]$AccountId = "",
    [string]$KmsKeyId = "alias/streamforge-phase1",
    [string]$CleanBucket = "",
    [string]$MetadataBucket = "",
    [string]$CuratedBucket = "",
    [string]$QuarantineBucket = "",
    [string]$AthenaResultsBucket = "",
    [string]$GlueDatabase = "streamforge_clean_db",
    [string]$CuratedTable = "customers_curated",
    [string]$GlueJobRole = "streamforge-glue-transform-role",
    [string]$GlueJobName = "streamforge-transform-customers",
    [string]$AthenaWorkgroup = "streamforge-phase3",
    [string]$AssetBucket = "",
    [string]$AssetPrefix = "glue-assets/phase3",
    [string]$InputPrefix = "",
    [string]$CuratedPrefix = "customers",
    [string]$QuarantinePrefix = "",
    [double]$MaxInvalidPercent = 10.0,
    [string]$PipelineVersion = "3.0.0",
    [string]$DateColumn = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-TempJsonFile {
    param([object]$Data)

    $path = Join-Path $env:TEMP ("streamforge-" + [guid]::NewGuid().ToString() + ".json")
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding ascii
    return $path
}

function Invoke-Aws {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & aws @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI command failed: aws $($Arguments -join ' ')"
    }
}

function Test-AwsCall {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $stdout = Join-Path $env:TEMP ("streamforge-stdout-" + [guid]::NewGuid().ToString() + ".log")
    $stderr = Join-Path $env:TEMP ("streamforge-stderr-" + [guid]::NewGuid().ToString() + ".log")
    $process = Start-Process -FilePath "aws" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return $process.ExitCode -eq 0
}

function Wait-GlueJobRun {
    param(
        [string]$JobName,
        [string]$JobRunId
    )

    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Seconds 15
        $state = aws glue get-job-run --job-name $JobName --run-id $JobRunId --region $Region --query "JobRun.JobRunState" --output text
        if ($state -eq "SUCCEEDED") {
            return
        }
        if ($state -in @("FAILED", "STOPPED", "TIMEOUT", "ERROR")) {
            $message = aws glue get-job-run --job-name $JobName --run-id $JobRunId --region $Region --query "JobRun.ErrorMessage" --output text
            throw "Glue job run failed with state ${state}: $message"
        }
    }

    throw "Timed out waiting for Glue job $JobName run $JobRunId"
}

function Invoke-AthenaQuery {
    param(
        [string]$Query,
        [string]$Database
    )

    $queryId = aws athena start-query-execution `
        --region $Region `
        --work-group $AthenaWorkgroup `
        --query-string $Query `
        --query-execution-context Database=$Database `
        --query "QueryExecutionId" `
        --output text

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start Athena query"
    }

    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Seconds 3
        $state = aws athena get-query-execution `
            --region $Region `
            --query-execution-id $queryId `
            --query "QueryExecution.Status.State" `
            --output text

        if ($state -eq "SUCCEEDED") {
            return $queryId
        }

        if ($state -in @("FAILED", "CANCELLED")) {
            $reason = aws athena get-query-execution `
                --region $Region `
                --query-execution-id $queryId `
                --query "QueryExecution.Status.StateChangeReason" `
                --output text
            throw "Athena query failed: $reason"
        }
    }

    throw "Timed out waiting for Athena query"
}

function Ensure-HardenedBucket {
    param(
        [string]$BucketName,
        [string]$KeyArn
    )

    $publicBlockFile = New-TempJsonFile @{
        BlockPublicAcls = $true
        IgnorePublicAcls = $true
        BlockPublicPolicy = $true
        RestrictPublicBuckets = $true
    }
    $ownershipFile = New-TempJsonFile @{
        Rules = @(
            @{ ObjectOwnership = "BucketOwnerEnforced" }
        )
    }
    $encryptionFile = New-TempJsonFile @{
        Rules = @(
            @{
                ApplyServerSideEncryptionByDefault = @{
                    SSEAlgorithm   = "aws:kms"
                    KMSMasterKeyID = $KeyArn
                }
                BucketKeyEnabled = $true
            }
        )
    }
    $bucketPolicyFile = New-TempJsonFile @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Sid       = "DenyInsecureTransport"
                Effect    = "Deny"
                Principal = "*"
                Action    = "s3:*"
                Resource  = @(
                    "arn:aws:s3:::$BucketName",
                    "arn:aws:s3:::$BucketName/*"
                )
                Condition = @{
                    Bool = @{
                        "aws:SecureTransport" = "false"
                    }
                }
            }
        )
    }

    if (-not (Test-AwsCall s3api head-bucket --bucket $BucketName --region $Region)) {
        Invoke-Aws s3api create-bucket --bucket $BucketName --region $Region
    }

    Invoke-Aws s3api put-public-access-block `
        --bucket $BucketName `
        --region $Region `
        --public-access-block-configuration file://$publicBlockFile
    Invoke-Aws s3api put-bucket-ownership-controls `
        --bucket $BucketName `
        --region $Region `
        --ownership-controls file://$ownershipFile
    Invoke-Aws s3api put-bucket-encryption `
        --bucket $BucketName `
        --region $Region `
        --server-side-encryption-configuration file://$encryptionFile
    Invoke-Aws s3api put-bucket-policy `
        --bucket $BucketName `
        --region $Region `
        --policy file://$bucketPolicyFile
}

if (-not $AccountId) {
    $AccountId = aws sts get-caller-identity --query "Account" --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve AWS account id"
    }
}

if (-not $CleanBucket) {
    $CleanBucket = "streamforge-clean-$AccountId-$Region"
}

if (-not $MetadataBucket) {
    $MetadataBucket = "streamforge-metadata-$AccountId-$Region"
}

if (-not $CuratedBucket) {
    $CuratedBucket = "streamforge-curated-$AccountId-$Region"
}

if (-not $QuarantineBucket) {
    $QuarantineBucket = "streamforge-quarantine-$AccountId-$Region"
}

if (-not $AthenaResultsBucket) {
    $AthenaResultsBucket = "streamforge-athena-results-$AccountId-$Region"
}

if (-not $AssetBucket) {
    $AssetBucket = $MetadataBucket
}

$keyArn = aws kms describe-key --region $Region --key-id $KmsKeyId --query "KeyMetadata.Arn" --output text
if ($LASTEXITCODE -ne 0) {
    throw "Failed to resolve KMS key ARN from $KmsKeyId"
}

Write-Host "Using account: $AccountId"
Write-Host "Using clean bucket: $CleanBucket"
Write-Host "Using metadata bucket: $MetadataBucket"
Write-Host "Using curated bucket: $CuratedBucket"
Write-Host "Using quarantine bucket: $QuarantineBucket"
Write-Host "Using Athena results bucket: $AthenaResultsBucket"
Write-Host "Using KMS key: $keyArn"

Ensure-HardenedBucket -BucketName $CuratedBucket -KeyArn $keyArn
Ensure-HardenedBucket -BucketName $QuarantineBucket -KeyArn $keyArn

$trustPolicyFile = New-TempJsonFile @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect    = "Allow"
            Principal = @{ Service = "glue.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }
    )
}

if (-not (Test-AwsCall iam get-role --role-name $GlueJobRole)) {
    Invoke-Aws iam create-role --role-name $GlueJobRole --assume-role-policy-document file://$trustPolicyFile
}

Invoke-Aws iam attach-role-policy `
    --role-name $GlueJobRole `
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

$rolePolicyFile = New-TempJsonFile @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect   = "Allow"
            Action   = @("s3:ListBucket")
            Resource = @(
                "arn:aws:s3:::$CleanBucket",
                "arn:aws:s3:::$MetadataBucket",
                "arn:aws:s3:::$CuratedBucket",
                "arn:aws:s3:::$QuarantineBucket"
            )
        },
        @{
            Effect   = "Allow"
            Action   = @("s3:GetObject")
            Resource = @(
                "arn:aws:s3:::$CleanBucket/*",
                "arn:aws:s3:::$MetadataBucket/*"
            )
        },
        @{
            Effect   = "Allow"
            Action   = @("s3:PutObject")
            Resource = @(
                "arn:aws:s3:::$CuratedBucket/*",
                "arn:aws:s3:::$QuarantineBucket/*"
            )
        },
        @{
            Effect   = "Allow"
            Action   = @("kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey")
            Resource = @($keyArn)
        }
    )
}

Invoke-Aws iam put-role-policy `
    --role-name $GlueJobRole `
    --policy-name streamforge-phase3-data-access `
    --policy-document file://$rolePolicyFile

$assetRoot = Join-Path $env:TEMP ("streamforge-phase3-assets-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
Copy-Item jobs\transform_helpers.py -Destination $assetRoot
Copy-Item jobs\transform_job.py -Destination $assetRoot
$packageZip = Join-Path $env:TEMP ("streamforge-phase3-jobs-" + [guid]::NewGuid().ToString() + ".zip")
Compress-Archive -Path (Join-Path $assetRoot "transform_helpers.py") -DestinationPath $packageZip

$scriptKey = ($AssetPrefix.Trim("/") + "/transform_job.py").TrimStart("/")
$packageKey = ($AssetPrefix.Trim("/") + "/jobs_package.zip").TrimStart("/")
Invoke-Aws s3 cp "$assetRoot\transform_job.py" "s3://$AssetBucket/$scriptKey" --region $Region
Invoke-Aws s3 cp $packageZip "s3://$AssetBucket/$packageKey" --region $Region

$createWorkgroupFile = New-TempJsonFile @{
    ResultConfiguration = @{
        OutputLocation = "s3://$AthenaResultsBucket/results/"
        EncryptionConfiguration = @{
            EncryptionOption = "SSE_KMS"
            KmsKey           = $keyArn
        }
    }
    EnforceWorkGroupConfiguration = $true
    PublishCloudWatchMetricsEnabled = $true
}

$updateWorkgroupFile = New-TempJsonFile @{
    ResultConfigurationUpdates = @{
        OutputLocation = "s3://$AthenaResultsBucket/results/"
        EncryptionConfiguration = @{
            EncryptionOption = "SSE_KMS"
            KmsKey           = $keyArn
        }
    }
    EnforceWorkGroupConfiguration = $true
    PublishCloudWatchMetricsEnabled = $true
}

if (Test-AwsCall athena get-work-group --work-group $AthenaWorkgroup --region $Region) {
    Invoke-Aws athena update-work-group `
        --work-group $AthenaWorkgroup `
        --region $Region `
        --configuration-updates file://$updateWorkgroupFile
} else {
    Invoke-Aws athena create-work-group `
        --name $AthenaWorkgroup `
        --region $Region `
        --configuration file://$createWorkgroupFile `
        --description "Phase 3 Athena workgroup for StreamForge"
}

$jobRoleArn = "arn:aws:iam::${AccountId}:role/${GlueJobRole}"
$defaultArguments = @{
    "--job-language" = "python"
    "--enable-metrics" = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--extra-py-files" = "s3://$AssetBucket/$packageKey"
    "--INPUT_BUCKET" = $CleanBucket
    "--METADATA_BUCKET" = $MetadataBucket
    "--CURATED_BUCKET" = $CuratedBucket
    "--QUARANTINE_BUCKET" = $QuarantineBucket
    "--METADATA_PREFIX" = "metadata"
    "--CURATED_PREFIX" = $CuratedPrefix
    "--DATABASE_NAME" = $GlueDatabase
    "--CURATED_TABLE" = $CuratedTable
    "--PIPELINE_VERSION" = $PipelineVersion
    "--MAX_INVALID_PERCENT" = [string]$MaxInvalidPercent
}
if ($InputPrefix) {
    $defaultArguments["--INPUT_PREFIX"] = $InputPrefix
}
if ($QuarantinePrefix) {
    $defaultArguments["--QUARANTINE_PREFIX"] = $QuarantinePrefix
}
if ($DateColumn) {
    $defaultArguments["--DATE_COLUMN"] = $DateColumn
}

$jobCommandFile = New-TempJsonFile @{
    Name = "glueetl"
    ScriptLocation = "s3://$AssetBucket/$scriptKey"
    PythonVersion = "3"
}
$defaultArgumentsFile = New-TempJsonFile $defaultArguments

if (Test-AwsCall glue get-job --job-name $GlueJobName --region $Region) {
    $jobUpdateFile = New-TempJsonFile @{
        Role = $jobRoleArn
        Command = @{
            Name = "glueetl"
            ScriptLocation = "s3://$AssetBucket/$scriptKey"
            PythonVersion = "3"
        }
        DefaultArguments = $defaultArguments
        GlueVersion = "4.0"
        WorkerType = "G.1X"
        NumberOfWorkers = 2
        ExecutionProperty = @{ MaxConcurrentRuns = 1 }
    }
    Invoke-Aws glue update-job `
        --job-name $GlueJobName `
        --region $Region `
        --job-update file://$jobUpdateFile
} else {
    Invoke-Aws glue create-job `
        --name $GlueJobName `
        --region $Region `
        --role $jobRoleArn `
        --command file://$jobCommandFile `
        --default-arguments file://$defaultArgumentsFile `
        --glue-version "4.0" `
        --worker-type "G.1X" `
        --number-of-workers 2 `
        --description "Phase 3 StreamForge curated transformation job" | Out-Null
}

$jobRunId = aws glue start-job-run --job-name $GlueJobName --region $Region --query "JobRunId" --output text
if ($LASTEXITCODE -ne 0) {
    throw "Failed to start Glue job $GlueJobName"
}
Wait-GlueJobRun -JobName $GlueJobName -JobRunId $jobRunId

$createCuratedTableQuery = @"
CREATE EXTERNAL TABLE IF NOT EXISTS $GlueDatabase.$CuratedTable (
  customer_id STRING,
  name STRING,
  email STRING,
  sales BIGINT,
  sales_category STRING,
  ingestion_timestamp STRING,
  processed_timestamp STRING,
  phase1_batch_id STRING,
  phase3_batch_id STRING,
  source_filename STRING,
  source_raw_key STRING,
  source_clean_key STRING,
  pipeline_version STRING
)
PARTITIONED BY (
  year STRING,
  month STRING,
  day STRING
)
STORED AS PARQUET
LOCATION 's3://$CuratedBucket/$CuratedPrefix/'
"@

$repairQuery = "MSCK REPAIR TABLE $GlueDatabase.$CuratedTable"
$verifyQuery = @"
SELECT source_filename, COUNT(*) AS row_count, MAX(sales_category) AS sample_sales_category
FROM $GlueDatabase.$CuratedTable
GROUP BY source_filename
ORDER BY source_filename
"@

$createId = Invoke-AthenaQuery -Query $createCuratedTableQuery -Database $GlueDatabase
$repairId = Invoke-AthenaQuery -Query $repairQuery -Database $GlueDatabase
$verifyId = Invoke-AthenaQuery -Query $verifyQuery -Database $GlueDatabase
$verifyResults = aws athena get-query-results --region $Region --query-execution-id $verifyId

Write-Host "Glue job run complete: $jobRunId"
Write-Host "Curated table query id: $createId"
Write-Host "Partition repair query id: $repairId"
Write-Host "Verification query id: $verifyId"
Write-Output $verifyResults
