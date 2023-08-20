def train(**kwargs):
    import logging
    from airflow.hooks.S3_hook import S3Hook
    import ray
    from ray.train.torch import TorchTrainer
    from ray.air.config import ScalingConfig, RunConfig
    from ray.tune import SyncConfig

    s3_hook = S3Hook(aws_conn_id="s3_connection")
    bucket = kwargs["bucket"]
    prefix = kwargs["prefix"]

    keys = s3_hook.list_keys(bucket, prefix=prefix)

    logging.info("===Training===")
    logging.info(f"===Dataset:{keys[1]}===")
