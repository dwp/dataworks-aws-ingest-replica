import logging
import boto3
import botocore
import os

sns_client = boto3.client("sns")
db_client = boto3.resource("dynamodb")
# paginator = db_client.get_paginator('list_objects')

def main():
    table_name = os.environ['TABLE_NAME']
    select = f"select JOB_STATUS, JOB_START_TIME from {table_name} where JOB_STATUS='started' order by JOB_START_TIME desc;"
    rs = db_client.execute_statement(Statement=select)
    print(rs)

def handler(event, context):
    main()
