"""
StreamForge Phase 6 - Migration Validation Lambda
Validates data integrity after Oracle to PostgreSQL migration
"""

import json
import os
import hashlib
from datetime import datetime
from typing import Dict, List, Any, Optional
import boto3
import pg8000.native

# Environment variables
AURORA_SECRET_ARN = os.environ.get('AURORA_SECRET_ARN')
AURORA_CLUSTER_ARN = os.environ.get('AURORA_CLUSTER_ARN')
S3_REPORTS_BUCKET = os.environ.get('S3_REPORTS_BUCKET')
ORACLE_SECRET_ARN = os.environ.get('ORACLE_SECRET_ARN', '')

# AWS clients
secrets_manager = boto3.client('secretsmanager')
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')


def get_db_credentials(secret_arn: str) -> Dict[str, str]:
    """Retrieve database credentials from Secrets Manager"""
    try:
        response = secrets_manager.get_secret_value(SecretId=secret_arn)
        secret = json.loads(response['SecretString'])
        return secret
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        raise


def connect_to_postgres(credentials: Dict[str, str]) -> pg8000.native.Connection:
    """Connect to Aurora PostgreSQL"""
    return pg8000.native.Connection(
        user=credentials['username'],
        password=credentials['password'],
        host=credentials['host'],
        port=credentials.get('port', 5432),
        database=credentials.get('dbname', 'postgres')
    )


def validate_row_counts(conn: pg8000.native.Connection,
                       oracle_counts: Optional[Dict[str, int]] = None) -> Dict[str, Any]:
    """Validate row counts match between source and target"""
    tables = [
        'regions', 'customers', 'suppliers', 'products', 'inventory',
        'employees', 'orders', 'order_items', 'payments', 'shipments'
    ]

    results = {
        'status': 'PASS',
        'tables': {},
        'mismatches': []
    }

    for table in tables:
        try:
            query = f"SELECT COUNT(*) FROM {table}"
            pg_count = conn.run(query)[0][0]

            table_result = {
                'postgresql_count': pg_count,
                'oracle_count': oracle_counts.get(table, 'N/A') if oracle_counts else 'N/A',
                'status': 'PASS'
            }

            # Compare with Oracle count if provided
            if oracle_counts and table in oracle_counts:
                if pg_count != oracle_counts[table]:
                    table_result['status'] = 'FAIL'
                    results['status'] = 'FAIL'
                    results['mismatches'].append({
                        'table': table,
                        'oracle': oracle_counts[table],
                        'postgresql': pg_count,
                        'difference': pg_count - oracle_counts[table]
                    })

            results['tables'][table] = table_result

        except Exception as e:
            results['status'] = 'ERROR'
            results['tables'][table] = {
                'status': 'ERROR',
                'error': str(e)
            }

    return results


def validate_primary_keys(conn: pg8000.native.Connection) -> Dict[str, Any]:
    """Validate primary key uniqueness"""
    results = {
        'status': 'PASS',
        'checks': []
    }

    pk_checks = [
        ('regions', 'region_id'),
        ('customers', 'customer_id'),
        ('suppliers', 'supplier_id'),
        ('products', 'product_id'),
        ('inventory', 'inventory_id'),
        ('employees', 'employee_id'),
        ('orders', 'order_id'),
        ('order_items', 'order_item_id'),
        ('payments', 'payment_id'),
        ('shipments', 'shipment_id')
    ]

    for table, pk_column in pk_checks:
        try:
            # Check for duplicates
            query = f"""
                SELECT {pk_column}, COUNT(*) as cnt
                FROM {table}
                GROUP BY {pk_column}
                HAVING COUNT(*) > 1
            """
            duplicates = conn.run(query)

            check_result = {
                'table': table,
                'primary_key': pk_column,
                'status': 'PASS' if len(duplicates) == 0 else 'FAIL',
                'duplicate_count': len(duplicates)
            }

            if duplicates:
                results['status'] = 'FAIL'
                check_result['duplicates'] = [row[0] for row in duplicates[:10]]  # First 10

            results['checks'].append(check_result)

        except Exception as e:
            results['status'] = 'ERROR'
            results['checks'].append({
                'table': table,
                'primary_key': pk_column,
                'status': 'ERROR',
                'error': str(e)
            })

    return results


def validate_foreign_keys(conn: pg8000.native.Connection) -> Dict[str, Any]:
    """Validate foreign key referential integrity"""
    results = {
        'status': 'PASS',
        'checks': []
    }

    fk_checks = [
        ('customers', 'region_id', 'regions', 'region_id'),
        ('suppliers', 'region_id', 'regions', 'region_id'),
        ('products', 'supplier_id', 'suppliers', 'supplier_id'),
        ('inventory', 'product_id', 'products', 'product_id'),
        ('employees', 'manager_id', 'employees', 'employee_id'),
        ('orders', 'customer_id', 'customers', 'customer_id'),
        ('orders', 'employee_id', 'employees', 'employee_id'),
        ('order_items', 'order_id', 'orders', 'order_id'),
        ('order_items', 'product_id', 'products', 'product_id'),
        ('payments', 'order_id', 'orders', 'order_id'),
        ('shipments', 'order_id', 'orders', 'order_id')
    ]

    for child_table, child_col, parent_table, parent_col in fk_checks:
        try:
            # Find orphaned records
            query = f"""
                SELECT COUNT(*)
                FROM {child_table} c
                LEFT JOIN {parent_table} p ON c.{child_col} = p.{parent_col}
                WHERE c.{child_col} IS NOT NULL AND p.{parent_col} IS NULL
            """
            orphan_count = conn.run(query)[0][0]

            check_result = {
                'child_table': child_table,
                'child_column': child_col,
                'parent_table': parent_table,
                'parent_column': parent_col,
                'status': 'PASS' if orphan_count == 0 else 'FAIL',
                'orphaned_records': orphan_count
            }

            if orphan_count > 0:
                results['status'] = 'FAIL'

            results['checks'].append(check_result)

        except Exception as e:
            results['status'] = 'ERROR'
            results['checks'].append({
                'child_table': child_table,
                'status': 'ERROR',
                'error': str(e)
            })

    return results


def validate_null_constraints(conn: pg8000.native.Connection) -> Dict[str, Any]:
    """Validate NOT NULL constraints"""
    results = {
        'status': 'PASS',
        'checks': []
    }

    # Tables with NOT NULL constraints
    not_null_checks = [
        ('regions', 'region_name'),
        ('regions', 'region_code'),
        ('customers', 'customer_name'),
        ('customers', 'email'),
        ('products', 'product_name'),
        ('products', 'product_code'),
        ('products', 'unit_price'),
        ('employees', 'first_name'),
        ('employees', 'last_name'),
        ('employees', 'email'),
        ('orders', 'order_number'),
        ('orders', 'customer_id'),
        ('order_items', 'order_id'),
        ('order_items', 'product_id'),
        ('order_items', 'quantity'),
        ('payments', 'order_id'),
        ('payments', 'payment_amount')
    ]

    for table, column in not_null_checks:
        try:
            query = f"""
                SELECT COUNT(*)
                FROM {table}
                WHERE {column} IS NULL
            """
            null_count = conn.run(query)[0][0]

            check_result = {
                'table': table,
                'column': column,
                'status': 'PASS' if null_count == 0 else 'FAIL',
                'null_count': null_count
            }

            if null_count > 0:
                results['status'] = 'FAIL'

            results['checks'].append(check_result)

        except Exception as e:
            results['status'] = 'ERROR'
            results['checks'].append({
                'table': table,
                'column': column,
                'status': 'ERROR',
                'error': str(e)
            })

    return results


def validate_data_consistency(conn: pg8000.native.Connection) -> Dict[str, Any]:
    """Validate business logic and data consistency"""
    results = {
        'status': 'PASS',
        'checks': []
    }

    consistency_checks = [
        {
            'name': 'Order totals match line items',
            'query': """
                SELECT o.order_id, o.order_total,
                       COALESCE(SUM(oi.line_total), 0) as calculated_total,
                       ABS(o.order_total - COALESCE(SUM(oi.line_total), 0)) as difference
                FROM orders o
                LEFT JOIN order_items oi ON o.order_id = oi.order_id
                GROUP BY o.order_id, o.order_total
                HAVING ABS(o.order_total - COALESCE(SUM(oi.line_total), 0)) > 0.01
            """
        },
        {
            'name': 'Inventory quantities are non-negative',
            'query': """
                SELECT COUNT(*)
                FROM inventory
                WHERE quantity_on_hand < 0 OR quantity_reserved < 0
            """
        },
        {
            'name': 'Available inventory calculation correct',
            'query': """
                SELECT COUNT(*)
                FROM inventory
                WHERE quantity_available != (quantity_on_hand - quantity_reserved)
            """
        },
        {
            'name': 'Payment amounts match order totals',
            'query': """
                SELECT COUNT(*)
                FROM orders o
                JOIN payments p ON o.order_id = p.order_id
                WHERE p.payment_status = 'COMPLETED'
                  AND ABS(p.payment_amount - (o.order_total + o.tax_amount + o.shipping_cost)) > 0.01
            """
        },
        {
            'name': 'Order line totals calculated correctly',
            'query': """
                SELECT COUNT(*)
                FROM order_items
                WHERE ABS(line_total - (quantity * unit_price * (1 - COALESCE(discount_pct, 0) / 100))) > 0.01
            """
        }
    ]

    for check in consistency_checks:
        try:
            result_rows = conn.run(check['query'])

            # Determine if check passed
            if check['query'].strip().upper().startswith('SELECT COUNT'):
                # For count queries, pass if count is 0
                issue_count = result_rows[0][0]
                passed = (issue_count == 0)
                check_result = {
                    'name': check['name'],
                    'status': 'PASS' if passed else 'FAIL',
                    'issue_count': issue_count
                }
            else:
                # For other queries, pass if no rows returned
                passed = (len(result_rows) == 0)
                check_result = {
                    'name': check['name'],
                    'status': 'PASS' if passed else 'FAIL',
                    'issue_count': len(result_rows)
                }

            if not passed:
                results['status'] = 'FAIL'

            results['checks'].append(check_result)

        except Exception as e:
            results['status'] = 'ERROR'
            results['checks'].append({
                'name': check['name'],
                'status': 'ERROR',
                'error': str(e)
            })

    return results


def calculate_checksums(conn: pg8000.native.Connection) -> Dict[str, Any]:
    """Calculate checksums for key tables"""
    results = {}

    tables = ['regions', 'customers', 'products', 'orders']

    for table in tables:
        try:
            # Simple checksum based on aggregated IDs and counts
            query = f"""
                SELECT
                    COUNT(*) as row_count,
                    SUM({table[:-1]}_id::bigint) as id_sum,
                    MAX({table[:-1]}_id::bigint) as max_id,
                    MIN({table[:-1]}_id::bigint) as min_id
                FROM {table}
            """
            result = conn.run(query)[0]

            checksum_data = f"{result[0]}|{result[1]}|{result[2]}|{result[3]}"
            checksum = hashlib.md5(checksum_data.encode()).hexdigest()

            results[table] = {
                'row_count': result[0],
                'id_sum': result[1],
                'max_id': result[2],
                'min_id': result[3],
                'checksum': checksum
            }

        except Exception as e:
            results[table] = {
                'status': 'ERROR',
                'error': str(e)
            }

    return results


def generate_validation_report(migration_id: str, validation_results: Dict[str, Any]) -> Dict[str, Any]:
    """Generate comprehensive validation report"""

    # Determine overall status
    overall_status = 'PASS'
    for key, result in validation_results.items():
        if isinstance(result, dict) and result.get('status') in ['FAIL', 'ERROR']:
            overall_status = 'FAIL'
            break

    report = {
        'migration_id': migration_id,
        'validation_timestamp': datetime.utcnow().isoformat(),
        'overall_status': overall_status,
        'source_database': 'Oracle 19c',
        'target_database': 'Aurora PostgreSQL',
        'validation_results': validation_results,
        'summary': {
            'total_checks': sum(
                len(v.get('checks', [])) if isinstance(v, dict) else 0
                for v in validation_results.values()
            ),
            'passed_checks': sum(
                sum(1 for c in v.get('checks', []) if c.get('status') == 'PASS')
                if isinstance(v, dict) else 0
                for v in validation_results.values()
            ),
            'failed_checks': sum(
                sum(1 for c in v.get('checks', []) if c.get('status') == 'FAIL')
                if isinstance(v, dict) else 0
                for v in validation_results.values()
            ),
            'errors': sum(
                sum(1 for c in v.get('checks', []) if c.get('status') == 'ERROR')
                if isinstance(v, dict) else 0
                for v in validation_results.values()
            )
        }
    }

    return report


def save_report_to_s3(report: Dict[str, Any], migration_id: str) -> str:
    """Save validation report to S3"""
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    key = f"migration_reports/{migration_id}/validation_{timestamp}.json"

    try:
        s3_client.put_object(
            Bucket=S3_REPORTS_BUCKET,
            Key=key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        return f"s3://{S3_REPORTS_BUCKET}/{key}"
    except Exception as e:
        print(f"Error saving report to S3: {e}")
        raise


def publish_metrics(report: Dict[str, Any]):
    """Publish validation metrics to CloudWatch"""
    try:
        metrics = [
            {
                'MetricName': 'ValidationStatus',
                'Value': 1 if report['overall_status'] == 'PASS' else 0,
                'Unit': 'None'
            },
            {
                'MetricName': 'TotalChecks',
                'Value': report['summary']['total_checks'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'PassedChecks',
                'Value': report['summary']['passed_checks'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'FailedChecks',
                'Value': report['summary']['failed_checks'],
                'Unit': 'Count'
            }
        ]

        cloudwatch.put_metric_data(
            Namespace='StreamForge/Migration',
            MetricData=metrics
        )
    except Exception as e:
        print(f"Error publishing metrics: {e}")


def lambda_handler(event, context):
    """
    Lambda handler for migration validation

    Event format:
    {
        "migration_id": "oracle-prod-001",
        "oracle_row_counts": {
            "regions": 5,
            "customers": 8,
            ...
        }
    }
    """
    print(f"Starting migration validation: {json.dumps(event)}")

    migration_id = event.get('migration_id', f"migration-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}")
    oracle_counts = event.get('oracle_row_counts', None)

    try:
        # Get PostgreSQL credentials
        pg_credentials = get_db_credentials(AURORA_SECRET_ARN)

        # Connect to Aurora PostgreSQL
        conn = connect_to_postgres(pg_credentials)

        # Run validation checks
        validation_results = {
            'row_counts': validate_row_counts(conn, oracle_counts),
            'primary_keys': validate_primary_keys(conn),
            'foreign_keys': validate_foreign_keys(conn),
            'null_constraints': validate_null_constraints(conn),
            'data_consistency': validate_data_consistency(conn),
            'checksums': calculate_checksums(conn)
        }

        # Generate report
        report = generate_validation_report(migration_id, validation_results)

        # Save report to S3
        report_url = save_report_to_s3(report, migration_id)
        report['report_url'] = report_url

        # Publish metrics
        publish_metrics(report)

        # Close connection
        conn.close()

        print(f"Validation complete. Status: {report['overall_status']}")
        print(f"Report saved to: {report_url}")

        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str)
        }

    except Exception as e:
        print(f"Validation error: {e}")
        import traceback
        traceback.print_exc()

        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'migration_id': migration_id
            })
        }
