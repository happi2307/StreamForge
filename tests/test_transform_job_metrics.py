from __future__ import annotations

from jobs.transform_job import JobConfig, _publish_pipeline_metrics


class RecordingCloudWatchClient:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    def put_metric_data(self, **kwargs: object) -> None:
        self.calls.append(kwargs)


def _config() -> JobConfig:
    return JobConfig(
        job_name="streamforge-transform-customers",
        input_bucket="clean",
        metadata_bucket="metadata",
        curated_bucket="curated",
        quarantine_bucket="quarantine",
        input_prefix="",
        metadata_prefix="metadata",
        curated_prefix="customers",
        quarantine_prefix="",
        database_name="streamforge_clean_db",
        curated_table="customers_curated",
        quarantine_table=None,
        pipeline_version="3.0.0",
        max_invalid_percent=10.0,
        date_column=None,
        environment="dev",
        metrics_namespace="StreamForge/Pipeline",
    )


def test_publish_pipeline_metrics_uses_batch_counts_without_customer_data() -> None:
    client = RecordingCloudWatchClient()

    _publish_pipeline_metrics(
        client,
        _config(),
        {"rows_read": 10, "rows_written": 8, "rows_quarantined": 2},
    )

    assert len(client.calls) == 1
    call = client.calls[0]
    assert call["Namespace"] == "StreamForge/Pipeline"
    assert call["MetricData"] == [
        {
            "MetricName": "RowsRead",
            "Dimensions": [
                {"Name": "Environment", "Value": "dev"},
                {"Name": "JobName", "Value": "streamforge-transform-customers"},
            ],
            "Unit": "Count",
            "Value": 10,
        },
        {
            "MetricName": "RowsWritten",
            "Dimensions": [
                {"Name": "Environment", "Value": "dev"},
                {"Name": "JobName", "Value": "streamforge-transform-customers"},
            ],
            "Unit": "Count",
            "Value": 8,
        },
        {
            "MetricName": "RowsQuarantined",
            "Dimensions": [
                {"Name": "Environment", "Value": "dev"},
                {"Name": "JobName", "Value": "streamforge-transform-customers"},
            ],
            "Unit": "Count",
            "Value": 2,
        },
    ]
