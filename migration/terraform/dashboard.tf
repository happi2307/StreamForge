# =====================================================
# StreamForge Phase 6 - CloudWatch Dashboard
# Monitoring for Migration Validation
# =====================================================

resource "aws_cloudwatch_dashboard" "migration" {
  dashboard_name = "${local.name_prefix}-migration-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Migration Custom Metrics
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["StreamForge/Migration", "ValidationStatus", {
              stat = "Average"
            }],
            [".", "TotalChecks", {
              stat = "Sum"
              yAxis = "right"
            }],
            [".", "FailedChecks", {
              stat = "Sum"
              yAxis = "right"
            }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Migration Validation Metrics"
          period  = 300
          yAxis = {
            left = {
              label = "Status (1=Pass)"
              showUnits = false
            }
            right = {
              label = "Check Count"
              showUnits = false
            }
          }
        }
      },
      # Validation Lambda Metrics
      {
        type = "metric"
        x    = 12
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", {
              stat = "Average"
              dimensions = {
                FunctionName = aws_lambda_function.validation.function_name
              }
            }],
            [".", "Errors", {
              stat = "Sum"
              yAxis = "right"
            }],
            [".", "Invocations", {
              stat = "Sum"
              yAxis = "right"
            }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Validation Lambda Performance"
          period  = 300
          yAxis = {
            left = {
              label = "Duration (ms)"
              showUnits = false
            }
            right = {
              label = "Count"
              showUnits = false
            }
          }
        }
      },
      # Recent Log Events
      {
        type = "log"
        x    = 0
        y    = 6
        width = 24
        height = 6
        properties = {
          query = <<-EOT
            SOURCE '${aws_cloudwatch_log_group.validation_lambda.name}'
            | fields @timestamp, @message
            | sort @timestamp desc
            | limit 100
          EOT
          region = data.aws_region.current.name
          title  = "Recent Validation Lambda Logs"
        }
      }
    ]
  })
}

# =====================================================
# Output
# =====================================================

output "migration_dashboard_url" {
  description = "URL to the CloudWatch migration dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.migration.dashboard_name}"
}
