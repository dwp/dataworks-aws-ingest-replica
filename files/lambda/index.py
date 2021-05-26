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
    print(f"environment variable: {os.environ['TABLE_NAME']}")
    rs = db_client.execute_statement(Statement= "select status, id from myTest where status='started' order by id desc")
    print(rs)

def handler(event, context):
    main()
