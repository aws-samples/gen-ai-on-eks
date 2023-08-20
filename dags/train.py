import logging
from sys import prefix
from airflow.hooks.S3_hook import S3Hook


def train(**kwargs):
    s3_hook = S3Hook(aws_conn_id="s3_connection")
    bucket = kwargs["bucket"]
    prefix = kwargs["prefix"]

    keys = s3_hook.list_keys(bucket, prefix=prefix)

    logging.info("===Training===")
    logging.info(f"===Dataset:{keys}===")
