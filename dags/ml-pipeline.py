from datetime import datetime, timedelta
import logging

from airflow import DAG
from airflow.models import Variable

from airflow.hooks.S3_hook import S3Hook

from airflow.operators.python_operator import PythonVirtualenvOperator
from airflow.operators.python import PythonOperator

from train import train
from serve import serve


def list_keys():
    hook = S3Hook(aws_conn_id="aws_credentials")
    bucket = Variable.get("s3_bucket")
    prefix = Variable.get("s3_prefix")
    logging.info(f"Listing Keys from {bucket}/{prefix}")
    keys = hook.list_keys(bucket, prefix=prefix)
    logging.info(keys)
    return keys


S3_BUCKET_NAME = "BUCKET_NAME"


# def train_ray():
#     from ray.job_submission import JobSubmissionClient

#     client = JobSubmissionClient(
#         "http://ray-cluster-kuberay-head-svc.ray-cluster.svc.cluster.local:8265"
#     )

#     # Submit job to Ray Cluster
#     kick_off_gpt2_training = (
#         "rm -rf finetune-gpt2-ray-test && git clone https://github.com/lusoal/finetune-gpt2-ray-test || true;"
#         " chmod +x finetune-gpt2-ray-test/llm-distributed-fine-tunning.py && python finetune-gpt2-ray-test/llm-distributed-fine-tunning.py --model='tiiuae/falcon-7b' --num-workers 4"
#     )

#     print("training")
#     submission_id = client.submit_job(
#         entrypoint=kick_off_gpt2_training,
#     )
#     print("Training: " + submission_id)


default_args = {
    "owner": "martinig",
    "depends_on_past": False,
    "start_date": datetime(2023, 8, 18),
    "retries": 0,
}

dag = DAG(
    "ml-pipeline",
    default_args=default_args,
    dagrun_timeout=timedelta(hours=1),
    schedule_interval="0 3 * * *",
)

# train_task = PythonVirtualenvOperator(
#     task_id="train", requirements="ray", python_callable=train_ray, dag=dag
# )

train_task = PythonOperator(task_id="train", python_callable=train, dag=dag)

serve_task = PythonOperator(task_id="serve", python_callable=serve, dag=dag)

train_task >> serve_task
