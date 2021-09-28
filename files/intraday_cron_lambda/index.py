import json
import logging
import os
import time
from uuid import uuid4
import base64
import ast
import boto3
from boto3.dynamodb.conditions import Attr

_logger = logging.getLogger()
_logger.setLevel(logging.INFO)

# Lambda environment vars
JOB_STATUS_TABLE = os.environ["job_status_table_name"]
SLACK_ALERT_ARN = os.environ["alert_topic_arn"]
LAUNCH_SNS_TOPIC_ARN = os.environ["launch_topic_arn"]
EMR_CONFIG_BUCKET = os.environ["emr_config_bucket"]
EMR_CONFIG_PREFIX = os.environ["emr_config_folder"]
COLLECTIONS_SECRET_NAME = os.environ["collections_secret_name"]

# Job Statuses & values stored in DynamoDB
TRIGGERED = "LAMBDA_TRIGGERED"  # this lambda was triggered
WAITING = "WAITING"  # this lambda is waiting up to 10 minutes for another cluster
DEFERRED = "DEFERRED"  # this lambda timed out waiting, did not launch emr
LAUNCHED = "EMR_LAUNCHED"  # this lambda posted to SNS topic to launch EMR cluster
PROCESSING = "EMR_PROCESSING"  # emr cluster has started processing data
COMPLETED = "EMR_COMPLETED"  # emr cluster processed the data successfully
EMR_FAILED = "EMR_FAILED"  # emr cluster couldn't process data successfully
LAMBDA_FAILED = "LAMBDA_FAILED"  # lambda encountered an error

# this lambda will not launch emr if another job is in one of these states
ACTIVE_STATES = [TRIGGERED, WAITING, LAUNCHED, PROCESSING, EMR_FAILED, LAMBDA_FAILED]


class PollingTimeoutError(TimeoutError):
    pass


def get_collections_list_from_aws(secrets_client, collections_secret_name):
    """Parse collections returned by AWS Secrets Manager"""
    return [
        f"{j['db']}:{j['table']}"
        for j in retrieve_secrets(secrets_client, collections_secret_name)[
            "collections_all"
        ].values()
    ]


def retrieve_secrets(secrets_client, secret_name):
    """Get b64 encoded secrets from AWS Secrets Manager"""
    response = secrets_client.get_secret_value(SecretId=secret_name)
    response_binary = response["SecretString"]
    response_decoded = base64.b64decode(response_binary).decode("utf-8")
    response_dict = ast.literal_eval(response_decoded)
    return response_dict


def update_db_items(table, collections, correlation_id: str, values: dict):
    _logger.info(f"Updating db item: {values}")
    updates = {key: {"Value": value} for key, value in values.items()}
    for collection in collections:
        table.update_item(
            Key={
                "CorrelationId": correlation_id,
                "Collection": collection,
            },
            AttributeUpdates=updates,
        )


def check_for_running_jobs(table, collections, correlation_id):
    _logger.debug("Checking for running jobs")
    results = table.scan(
        FilterExpression=Attr("JobStatus").is_in(ACTIVE_STATES)
        & Attr("CorrelationId").ne(correlation_id)
        & Attr("Collection").is_in(collections),
    )
    return results["Items"]


def poll_previous_jobs(correlation_id, collections, table, timeout=300):
    _logger.info("Polling for previous running jobs")
    start_time = time.time()

    running_jobs = check_for_running_jobs(table, collections, correlation_id)
    while running_jobs:
        _logger.info(
            f"Waited {round(time.time() - start_time)}/{timeout}"
            f" seconds for previous collections to complete:"
        )
        _logger.info(
            "\n".join(
                [
                    str({"topic": row["Collection"], "JobStatus": row["JobStatus"]})
                    for row in running_jobs
                ]
            )
        )
        if time.time() >= (start_time + timeout):
            update_db_items(table, collections, correlation_id, {"JobStatus": DEFERRED})
            raise PollingTimeoutError(
                f"Polling timeout ({timeout}s), job(s) still in progress"
            )
        time.sleep(5)
        running_jobs = check_for_running_jobs(table, collections, correlation_id)
    return True


def launch_cluster(
    correlation_id: str,
    triggered_time: int,
    collections,
    sns_client,
    job_table,
    topic_arn: str,
):
    # Cluster takes 10~15m to provision, this provides adequate time for the pipeline
    #   to ingest data up to the current timestamp into hbase.
    new_end_time = int(time.time() * 1000)

    cluster_overrides = json.dumps(
        {
            "s3_overrides": {
                "emr_launcher_config_s3_bucket": EMR_CONFIG_BUCKET,
                "emr_launcher_config_s3_folder": EMR_CONFIG_PREFIX,
            },
            "additional_step_args": {
                "spark-submit": [
                    "scheduled",
                    "--correlation_id",
                    str(correlation_id),
                    "--triggered_time",
                    str(triggered_time),
                    "--end_time",
                    str(new_end_time),
                    "--collections",
                ]
                + collections
            },
        }
    )
    _logger.info("Launching emr cluster")
    _logger.info("Collections: " + " ".join(collections))
    _logger.debug({"Cluster Overrides": cluster_overrides})
    _ = sns_client.publish(
        TopicArn=topic_arn,
        Message=cluster_overrides,
        Subject="Launch ingest-replica emr cluster",
    )
    update_db_items(job_table, collections, correlation_id, {"JobStatus": LAUNCHED})


def handler(event, context):
    correlation_id = str(uuid4())
    triggered_time = round(time.time() * 1000)
    _logger.info(
        {
            "correlation_id": correlation_id,
            "triggered_time": triggered_time,
        }
    )

    sns_client = boto3.client("sns")
    dynamodb = boto3.resource("dynamodb")
    job_table = dynamodb.Table(JOB_STATUS_TABLE)
    secrets_client = boto3.session.Session().client(service_name="secretsmanager")

    collections = get_collections_list_from_aws(secrets_client, COLLECTIONS_SECRET_NAME)
    _logger.info({"collections": collections})
    update_db_items(
        job_table,
        collections,
        correlation_id,
        {"JobStatus": TRIGGERED, "TriggeredTime": triggered_time},
    )

    try:
        update_db_items(job_table, collections, correlation_id, {"JobStatus": WAITING})
        poll_previous_jobs(
            correlation_id=correlation_id, collections=collections, table=job_table
        )
        launch_cluster(
            correlation_id=correlation_id,
            triggered_time=triggered_time,
            collections=collections,
            sns_client=sns_client,
            job_table=job_table,
            topic_arn=LAUNCH_SNS_TOPIC_ARN,
        )
    except PollingTimeoutError:
        # Dynamodb already updated with status
        alert_message = json.dumps(
            {
                "severity": "High",
                "notification_type": "Warning",
                "title_text": "Intraday Cluster Launch Deferred - Previous cluster still running",
            }
        )
        sns_client.publish(
            TargetArn=SLACK_ALERT_ARN,
            Message=alert_message,
        )
        raise
    except Exception:
        # Update Dynamodb with failure status
        update_db_items(
            job_table, collections, correlation_id, {"JobStatus": LAMBDA_FAILED}
        )

        alert_message = json.dumps(
            {
                "severity": "Critical",
                "notification_type": "Error",
                "title_text": "intraday_cron_launcher Lambda Failed",
                "log_with_here": "true",
            }
        )
        sns_client.publish(
            TargetArn=SLACK_ALERT_ARN,
            Message=alert_message,
        )
        raise
