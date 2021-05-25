#!/usr/bin/python3
import datetime
import json
import logging
import boto3
import botocore
import os

sns_client = boto3.client('sns')

def main():
    print(f"environment variable: {os.environ['TABLE_NAME']}")

def handler(event, context):
    main()
