import json
import logging
import os
import time
from uuid import uuid4

import boto3
from boto3.dynamodb.conditions import Attr, Key

_logger = logging.getLogger()
_logger.setLevel(logging.INFO)

# Lambda environment vars
JOB_STATUS_TABLE = os.environ["job_status_table_name"]
LAUNCH_SNS_TOPIC_ARN = os.environ["sns_topic_arn"]
EMR_CONFIG_BUCKET = os.environ["emr_config_bucket"]
EMR_CONFIG_PREFIX = os.environ["emr_config_folder"]

# Job Statuses & values stored in DynamoDB
TRIGGERED = "LAMBDA_TRIGGERED"  # this lambda was triggered
WAITING = "WAITING"  # this lambda is waiting up to 10 minutes for another cluster
DEFERRED = "DEFERRED"  # this lambda timed out waiting, did not launch emr
LAUNCHED = "LAUNCHED"  # this lambda posted to SNS topic to launch EMR cluster
PROCESSING = "PROCESSING"  # emr cluster has started processing data
COMPLETED = "COMPLETED"  # emr cluster processed the data successfully
EMR_FAILED = "EMR_FAILED"  # emr cluster couldn't process data successfully
LAMBDA_FAILED = "LAMBDA_FAILED"  # lambda encountered an error

# this lambda will not launch emr if another job is in one of these states
ACTIVE_STATES = [TRIGGERED, WAITING, LAUNCHED, PROCESSING, EMR_FAILED, LAMBDA_FAILED]


class PollingTimeoutError(TimeoutError):
    pass


def update_db_item(table, correlation_id: str, triggered_time: int, values: dict):
    updates = {key: {"Value": value} for key, value in values.items()}

    table.update_item(
        Key={
            "CorrelationId": correlation_id,
            "TriggeredTime": triggered_time,
        },
        AttributeUpdates=updates,
    )


def check_for_running_jobs(table, correlation_id):
    _logger.debug("Checking for running jobs")
    results = table.scan(
        IndexName="StatusIndex",
        FilterExpression=Attr("JobStatus").is_in(ACTIVE_STATES)
        & Attr("CorrelationId").ne(correlation_id),
    )
    return results["Items"]


def poll_previous_jobs(correlation_id, triggered_time, table, timeout=300):
    update_db_item(table, correlation_id, triggered_time, {"JobStatus": WAITING})
    start_time = time.time()

    while check_for_running_jobs(table, correlation_id):
        _logger.info(
            f"Waited {round(time.time() - start_time)}/{timeout}"
            f" seconds for previous jobs to complete"
        )
        if time.time() >= (start_time + timeout):
            update_db_item(
                table, correlation_id, triggered_time, {"JobStatus": DEFERRED}
            )
            raise PollingTimeoutError(
                f"Polling timeout ({timeout}s), job(s) still in progress"
            )
        time.sleep(5)
    return True


def get_job_context(sns_client, table):
    # Get latest timestamp for data processed
    _logger.debug("getting timestamps from previous jobs")
    response = table.query(
        IndexName="StatusIndex",
        KeyConditionExpression=Key("JobStatus").eq("COMPLETED"),
        ProjectionExpression="TriggeredTime, ProcessedDataStart, ProcessedDataEnd",
        ScanIndexForward=False,
    )

    filtered_records = [
        record for record in response["Items"] if record.get("ProcessedDataEnd")
    ]
    end_time = filtered_records[0].get("ProcessedDataEnd") if filtered_records else 0
    return end_time


def launch_cluster(
    correlation_id: str, triggered_time, sns_client, job_table, topic_arn: str
):
    previous_end_time = get_job_context(sns_client, job_table)
    buffer = 1000 * 60 * 5  # 5 minutes in milliseconds
    new_end_time = round(time.time() * 1000) - buffer

    cluster_config = json.dumps(
        {
            "s3_overrides": {
                "emr_launcher_config_s3_bucket": EMR_CONFIG_BUCKET,
                "emr_launcher_config_s3_folder": EMR_CONFIG_PREFIX,
            },
            "additional_step_args": {
                "spark-submit": [
                    "--start_time",
                    str(previous_end_time),
                    "--end_time",
                    str(new_end_time),
                    "--correlation_id",
                    str(correlation_id),
                    "--triggered_time",
                    str(triggered_time),
                ]
            },
        }
    )
    _logger.info("Launching emr cluster")
    _logger.debug({"Cluster Config": cluster_config})
    _ = sns_client.publish(
        TopicArn=topic_arn,
        Message=cluster_config,
        Subject="Launch ingest-replica emr cluster",
    )
    update_db_item(job_table, correlation_id, triggered_time, {"JobStatus": LAUNCHED})


def handler(event, context):
    correlation_id = str(uuid4())
    triggered_time = round(time.time() * 1000)

    sns_client = boto3.client("sns")
    dynamodb = boto3.resource("dynamodb")
    job_table = dynamodb.Table(JOB_STATUS_TABLE)

    update_db_item(job_table, correlation_id, triggered_time, {"JobStatus": TRIGGERED})

    try:
        poll_previous_jobs(correlation_id, triggered_time, job_table)
        launch_cluster(
            correlation_id, triggered_time, sns_client, job_table, LAUNCH_SNS_TOPIC_ARN
        )
    except PollingTimeoutError:
        # Dynamodb already updated with status
        raise
    except Exception:
        # Update Dynamodb with failure status
        update_db_item(
            job_table, correlation_id, triggered_time, {"JobStatus": LAMBDA_FAILED}
        )
        raise
