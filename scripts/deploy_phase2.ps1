param(
    [string]$Region = "us-east-1",
    [string]$AccountId = "",
    [string]$KmsKeyId = "alias/streamforge-phase1",
    [string]$CleanBucket = "",
    [string]$AthenaResultsBucket = "",
    [string]$GlueDatabase = "streamforge_clean_db",
    [string]$GlueCrawlerRole = "streamforge-glue-crawler-role",
    [string]$GlueCrawler = "streamforge-clean-crawler",
    [string]$AthenaWorkgroup = "streamforge-phase2"
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

    & aws @Arguments *> $null
    return $LASTEXITCODE -eq 0
}

function Wait-CrawlerReady {
    param([string]$Name)

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 6
        $state = aws glue get-crawler --name $Name --region $Region --query "Crawler.State" --output text
        if ($state -eq "READY") {
            $status = aws glue get-crawler --name $Name --region $Region --query "Crawler.LastCrawl.Status" --output text
            if ($status -ne "SUCCEEDED") {
                throw "Crawler finished but did not succeed: $status"
            }
            return
        }
    }

    throw "Timed out waiting for crawler $Name"
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

    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        $state = aws athena get-query-execution `
            --region $Region `
            --query-execution-id $queryId `
            --query "QueryExecution.Status.State" `
            --output text

        if ($state -eq "SUCCEEDED") {
            return $queryId
        }

        if ($state -eq "FAILED" -or $state -eq "CANCELLED") {
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

if (-not $AccountId) {
    $AccountId = aws sts get-caller-identity --query "Account" --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve AWS account id"
    }
}

if (-not $CleanBucket) {
    $CleanBucket = "streamforge-clean-$AccountId-$Region"
}

if (-not $AthenaResultsBucket) {
    $AthenaResultsBucket = "streamforge-athena-results-$AccountId-$Region"
}

$keyArn = aws kms describe-key --region $Region --key-id $KmsKeyId --query "KeyMetadata.Arn" --output text
if ($LASTEXITCODE -ne 0) {
    throw "Failed to resolve KMS key ARN from $KmsKeyId"
}

Write-Host "Using account: $AccountId"
Write-Host "Using clean bucket: $CleanBucket"
Write-Host "Using Athena results bucket: $AthenaResultsBucket"
Write-Host "Using KMS key: $keyArn"

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
                KMSMasterKeyID = $keyArn
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
                "arn:aws:s3:::$AthenaResultsBucket",
                "arn:aws:s3:::$AthenaResultsBucket/*"
            )
            Condition = @{
                Bool = @{
                    "aws:SecureTransport" = "false"
                }
            }
        }
    )
}

if (-not (Test-AwsCall s3api head-bucket --bucket $AthenaResultsBucket --region $Region)) {
    Invoke-Aws s3api create-bucket --bucket $AthenaResultsBucket --region $Region
}

Invoke-Aws s3api put-public-access-block `
    --bucket $AthenaResultsBucket `
    --region $Region `
    --public-access-block-configuration file://$publicBlockFile
Invoke-Aws s3api put-bucket-ownership-controls `
    --bucket $AthenaResultsBucket `
    --region $Region `
    --ownership-controls file://$ownershipFile
Invoke-Aws s3api put-bucket-encryption `
    --bucket $AthenaResultsBucket `
    --region $Region `
    --server-side-encryption-configuration file://$encryptionFile
Invoke-Aws s3api put-bucket-policy `
    --bucket $AthenaResultsBucket `
    --region $Region `
    --policy file://$bucketPolicyFile

$databaseFile = New-TempJsonFile @{
    Name        = $GlueDatabase
    Description = "Phase 2 Glue catalog for StreamForge clean customer data"
}

if (-not (Test-AwsCall glue get-database --name $GlueDatabase --region $Region)) {
    Invoke-Aws glue create-database --region $Region --database-input file://$databaseFile
}

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

if (-not (Test-AwsCall iam get-role --role-name $GlueCrawlerRole)) {
    Invoke-Aws iam create-role --role-name $GlueCrawlerRole --assume-role-policy-document file://$trustPolicyFile
}

Invoke-Aws iam attach-role-policy `
    --role-name $GlueCrawlerRole `
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

$glueInlinePolicyFile = New-TempJsonFile @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect   = "Allow"
            Action   = @("s3:ListBucket")
            Resource = @("arn:aws:s3:::$CleanBucket")
        },
        @{
            Effect   = "Allow"
            Action   = @("s3:GetObject")
            Resource = @("arn:aws:s3:::$CleanBucket/*")
        },
        @{
            Effect   = "Allow"
            Action   = @("kms:Decrypt", "kms:DescribeKey")
            Resource = @($keyArn)
        }
    )
}

Invoke-Aws iam put-role-policy `
    --role-name $GlueCrawlerRole `
    --policy-name streamforge-glue-clean-read `
    --policy-document file://$glueInlinePolicyFile

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
        --description "Phase 2 Athena workgroup for StreamForge"
}

$crawlerTargetsFile = New-TempJsonFile @{
    S3Targets = @(
        @{ Path = "s3://$CleanBucket/" }
    )
}

$schemaChangePolicyFile = New-TempJsonFile @{
    UpdateBehavior = "UPDATE_IN_DATABASE"
    DeleteBehavior = "LOG"
}

$glueRoleArn = "arn:aws:iam::${AccountId}:role/${GlueCrawlerRole}"
if (Test-AwsCall glue get-crawler --name $GlueCrawler --region $Region) {
    Invoke-Aws glue update-crawler `
        --name $GlueCrawler `
        --region $Region `
        --role $glueRoleArn `
        --database-name $GlueDatabase `
        --targets file://$crawlerTargetsFile `
        --schema-change-policy file://$schemaChangePolicyFile
} else {
    Invoke-Aws glue create-crawler `
        --name $GlueCrawler `
        --region $Region `
        --role $glueRoleArn `
        --database-name $GlueDatabase `
        --targets file://$crawlerTargetsFile `
        --schema-change-policy file://$schemaChangePolicyFile `
        --description "Phase 2 crawler for StreamForge clean customer data"
}

Start-Sleep -Seconds 12
Invoke-Aws glue start-crawler --name $GlueCrawler --region $Region
Wait-CrawlerReady -Name $GlueCrawler

$createTableQuery = @"
CREATE EXTERNAL TABLE IF NOT EXISTS $GlueDatabase.customers (
  customer_id BIGINT,
  name STRING,
  email STRING,
  sales BIGINT
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
WITH SERDEPROPERTIES (
  'field.delim' = ','
)
STORED AS TEXTFILE
LOCATION 's3://$CleanBucket/'
TBLPROPERTIES (
  'skip.header.line.count' = '1'
)
"@

$query1 = @"
SELECT customer_id, name, email, sales
FROM $GlueDatabase.customers
ORDER BY customer_id
"@

$query2 = @"
SELECT COUNT(*) AS total_customers, SUM(sales) AS total_sales, AVG(sales) AS average_sales
FROM $GlueDatabase.customers
"@

$createId = Invoke-AthenaQuery -Query $createTableQuery -Database $GlueDatabase
$query1Id = Invoke-AthenaQuery -Query $query1 -Database $GlueDatabase
$query2Id = Invoke-AthenaQuery -Query $query2 -Database $GlueDatabase

Write-Host "Created or verified Athena table with query id: $createId"
Write-Host "Verified ordered customer query with id: $query1Id"
Write-Host "Verified aggregate query with id: $query2Id"
Write-Host "Phase 2 deployment complete."
