def serve(bucket, prefix):
    import logging
    from airflow.hooks.S3_hook import S3Hook
    from ray.job_submission import JobSubmissionClient

    s3_hook = S3Hook(aws_conn_id="s3_connection")

    keys = s3_hook.list_keys(bucket, prefix=prefix)

    logging.info("===Serving===")
    logging.info(f"===Model:{keys[1]}===")

    ray_client = JobSubmissionClient(
        "http://ray-cluster-kuberay-head-svc.ray-cluster.svc.cluster.local:8265"
    )

    ray_serving = (
        "rm -rf fm-ops-eks && git clone -b feat/nvidia_gpu_operator https://github.com/lusoal/fm-ops-eks || true;"
        "chmod +x fm-ops-eks/scripts/serve_llm.py && python fm-ops-eks/scripts/serve_llm.py"
    )

    submission_id = ray_client.submit_job(
        entrypoint=ray_serving,
        runtime_env={"pip": ["boto3"]},
    )

    logging.info(f"===Submission ID:{submission_id}===")
