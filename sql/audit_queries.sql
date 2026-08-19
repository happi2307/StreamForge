-- StreamForge Phase 5 — operational audit queries.
-- Ad-hoc queries for operators inspecting load history and failures.

-- Recent batches, newest first.
SELECT
    batch_id,
    source_file,
    status,
    records_loaded,
    records_updated,
    records_failed,
    duration_ms,
    start_time,
    end_time
FROM audit.batch_metadata
ORDER BY start_time DESC NULLS LAST
LIMIT 50;

-- Failed batches needing attention.
SELECT batch_id, source_file, records_failed, end_time
FROM audit.batch_metadata
WHERE status = 'FAILED'
ORDER BY end_time DESC NULLS LAST;

-- Batches skipped as already-processed (idempotency in action).
SELECT batch_id, source_file, end_time
FROM audit.batch_metadata
WHERE status = 'SKIPPED'
ORDER BY end_time DESC NULLS LAST;

-- Rejected records for a specific batch (bind :batch_id).
SELECT customer_id, error_message, error_timestamp, source_file
FROM audit.load_errors
WHERE batch_id = :batch_id
ORDER BY error_timestamp;

-- Load throughput summary over the last 24 hours.
SELECT
    count(*)                          AS batches,
    sum(records_loaded)               AS total_loaded,
    sum(records_updated)              AS total_updated,
    sum(records_failed)               AS total_failed,
    round(avg(duration_ms))           AS avg_duration_ms
FROM audit.batch_metadata
WHERE start_time >= now() - interval '24 hours';

-- Error-rate leaderboard: sources with the most rejected records.
SELECT source_file, count(*) AS errors
FROM audit.load_errors
GROUP BY source_file
ORDER BY errors DESC
LIMIT 20;
