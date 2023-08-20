from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable

from airflow.sensors.s3_key_sensor import S3KeySensor
from airflow.operators.python import PythonOperator

from train import train
from serve import serve

default_args = {
    "owner": "fmops",
    "depends_on_past": False,
    "start_date": datetime(2023, 8, 18),
    "retries": 0,
}

dag = DAG(
    "ml-pipeline",
    default_args=default_args,
    dagrun_timeout=timedelta(hours=1),
    schedule_interval="@daily",
)

bucket = Variable.get("s3_bucket")
prefix = Variable.get("s3_prefix")

s3_sensor = S3KeySensor(
    task_id="s3_file_check",
    poke_interval=60,
    timeout=180,
    soft_fail=False,
    retries=2,
    bucket_key=prefix,
    bucket_name=bucket,
    aws_conn_id="s3_connection",
    dag=dag,
)

train_task = PythonOperator(
    task_id="train",
    python_callable=train,
    op_kwargs={"bucket": bucket, "prefix": prefix},
    dag=dag,
)

serve_task = PythonOperator(task_id="serve", python_callable=serve, dag=dag)

s3_sensor >> train_task >> serve_task
