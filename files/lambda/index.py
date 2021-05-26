import logging
import boto3
import botocore
import os

sns_client = boto3.client("sns")
db_client = boto3.client("dynamodb")

def main():
    table_name = os.environ['TABLE_NAME']
    select = f"select job_status, job_start_time from {table_name} where status='started' order by job_start_time desc;"
    rs = db_client.execute_statement(Statement=select)
    print(rs)

def handler(event, context):
    main()
