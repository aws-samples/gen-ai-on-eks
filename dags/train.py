def train(bucket, prefix):
    import logging
    from airflow.hooks.S3_hook import S3Hook
    from ray.job_submission import JobSubmissionClient

    s3_hook = S3Hook(aws_conn_id="s3_connection")

    keys = s3_hook.list_keys(bucket, prefix=prefix)

    logging.info("===Training===")
    logging.info(f"===Dataset:{keys[1]}===")

    ray_client = JobSubmissionClient(
        "http://ray-cluster-kuberay-head-svc.ray-cluster.svc.cluster.local:8265"
    )

    ray_training = (
        "rm -rf fm-ops-eks && git clone -b feat/nvidia_gpu_operator https://github.com/lusoal/fm-ops-eks || true;"
        "chmod +x fm-ops-eks/scripts/train_llm.py && python fm-ops-eks/scripts/train_llm.py --num-workers 4"
    )

    submission_id = ray_client.submit_job(
        entrypoint=ray_training,
    )

    logging.info(f"===Submission ID:{submission_id}===")
