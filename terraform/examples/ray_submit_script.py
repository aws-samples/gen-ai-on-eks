from ray.job_submission import JobSubmissionClient

client = JobSubmissionClient("http://localhost:8265")

# Submit job to Ray Cluster
kick_off_gpt2_training = (
    "rm -rf finetune-gpt2-ray-test && git clone https://github.com/lusoal/finetune-gpt2-ray-test || true;"
    " chmod +x finetune-gpt2-ray-test/llm-distributed-fine-tunning.py && python finetune-gpt2-ray-test/llm-distributed-fine-tunning.py --model='tiiuae/falcon-7b' --num-workers 4 --no-deepspeed"
)

submission_id = client.submit_job(
    entrypoint=kick_off_gpt2_training,
)