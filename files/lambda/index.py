#!/usr/bin/python3
import datetime
import json
import logging
import boto3
import botocore
import os

sns_client = boto3.client("sns")
db_client = boto3.client("dynamodb")

def main():
    table_name = {os.environ['TABLE_NAME']}
    select = f"select status, id from {table_name} where status='started' order by id desc"
    rs = db_client.execute_statement(Statement=f"{select}")
    print(rs)

def handler(event, context):
    main()
