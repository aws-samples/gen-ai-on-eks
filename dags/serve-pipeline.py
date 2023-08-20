from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable

from airflow.sensors.s3_key_sensor import S3KeySensor
from airflow.operators.python_operator import PythonVirtualenvOperator

from serve import serve

default_args = {
    "owner": "fmops",
    "depends_on_past": False,
    "start_date": datetime(2023, 8, 18),
    "retries": 0,
}

dag = DAG(
    "serve-pipeline",
    default_args=default_args,
    dagrun_timeout=timedelta(hours=1),
    schedule_interval="@daily",
)

bucket = Variable.get("s3_bucket")
prefix = "model"
training_key = "model.tar.gz"

s3_sensor = S3KeySensor(
    task_id="s3_file_check",
    poke_interval=60,
    timeout=180,
    soft_fail=False,
    retries=2,
    bucket_key=f"{prefix}/{training_key}",
    bucket_name=bucket,
    aws_conn_id="s3_connection",
    dag=dag,
)

serve_task = PythonVirtualenvOperator(
    task_id="serve",
    python_callable=serve,
    requirements="ray",
    op_kwargs={"bucket": bucket, "prefix": prefix},
    dag=dag,
)

s3_sensor >> serve_task
