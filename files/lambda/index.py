import logging
import boto3
import time
import os
import sys
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

sns_client = boto3.client("sns")
db_client = boto3.resource('dynamodb')
paginator = db_client.meta.client.get_paginator('query')


def setup_logging(log_level, log_path=None):
    logger = logging.getLogger()
    for old_handler in logger.handlers:
        logger.removeHandler(old_handler)

    if log_path is None:
        handler = logging.StreamHandler(sys.stdout)
    else:
        handler = logging.FileHandler(log_path)

    json_format = (
        "{ 'timestamp': '%(asctime)s', 'log_level': '%(levelname)s', 'message': "
        "'%(message)s' } "
    )
    handler.setFormatter(logging.Formatter(json_format))
    logger.addHandler(handler)
    new_level = logging.getLevelName(log_level.upper())
    logger.setLevel(new_level)

    return logger


def get_dynamodb(table_name):
    try:
        page_iterator = paginator.paginate(TableName=table_name,
                                           KeyConditionExpression=Key('JOB_STATUS').eq('started'),
                                           ScanIndexForward=False,
                                           PaginationConfig={'MaxItems': 1})
    except ClientError as error:
        _logger.info(error)
    else:
        return page_iterator


def publish_sns(topic, msg, subject="HBASE incremental refresh job"):
    try:
        rs = sns_client.publish(TopicArn = topic,
                                Message = msg,
                                Subject = subject,
                                )
    except ClientError as error:
        _logger.info(error)
    else:
        return rs


def main():
    _logger = setup_logging(
        log_level="INFO"
    )
    table_name = os.environ["table_name"]
    s3_bucket = os.environ["bucket"]
    s3_folder = os.environ["folder"]
    topic = os.environ["topic"]
    msg = f"""{{
    "s3_overrides": {{
        "emr_launcher_config_s3_bucket": {s3_bucket},
        "emr_launcher_config_s3_folder": {s3_folder}
    }}
}}"""
    counter = 0

    while counter < 3:
        status = get_dynamodb(table_name)
        for page in status:
            if not page.get("Items", None):
                _logger.info(f"Launching EMR cluster")
                rs = publish_sns(topic, msg)
                _logger.info(rs)
                counter = 3
            else:
                _logger.info(f"Previous job is still running will check the status in another 5 minutes {page}")
                time.sleep(300)
                counter += 1

def handler(event, context):
    main()
