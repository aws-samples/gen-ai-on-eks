import os
import boto3
import ray
import pandas as pd

from ray import serve
from starlette.requests import Request


ray.init(
    address="auto",
    namespace="serve",
    runtime_env={
        "pip": [
            "datasets",
            "evaluate",
            # Latest combination of accelerate==0.19.0 and transformers==4.29.0
            # seems to have issues with DeepSpeed process group initialization,
            # and will result in a batch_size validation problem.
            # TODO(jungong) : get rid of the pins once the issue is fixed.
            "accelerate==0.20.3",
            "transformers==4.26.0",
            "torch>=1.12.0",
            "torch"
        ]
    }
)

@serve.deployment(ray_actor_options={"num_gpus": 1})
class PredictDeployment:
    def __init__(self, model_id: str, revision: str = None):
        from transformers import AutoModelForCausalLM, AutoTokenizer
        import torch

        self.model = AutoModelForCausalLM.from_pretrained(
            model_id,
            revision=revision,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True,
            device_map="auto",  # automatically makes use of all GPUs available to the Actor
        )
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)

    def generate(self, text: str) -> pd.DataFrame:
        input_ids = self.tokenizer(text, return_tensors="pt").input_ids.to(
            self.model.device
        )

        gen_tokens = self.model.generate(
            input_ids,
            do_sample=True,
            temperature=0.9,
            max_length=100,
        )
        return pd.DataFrame(
            self.tokenizer.batch_decode(gen_tokens), columns=["responses"]
        )

    async def __call__(self, http_request: Request) -> str:
        json_request: str = await http_request.json()
        prompts = []
        for prompt in json_request:
            text = prompt["text"]
            if isinstance(text, list):
                prompts.extend(text)
            else:
                prompts.append(text)
        return self.generate(prompts)

# Initialize S3 client
s3 = boto3.client("s3")
bucket = "fm-ops-datasets"
model_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/pytorch_model.bin"
tokenizer_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/tokenizer.json"
config_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/config.json"

# Download model and tokenizer from S3 to a local directory
local_dir = "local_model"
os.makedirs(local_dir, exist_ok=True)
s3.download_file(bucket, model_key, "local_model/pytorch_model.bin")
s3.download_file(bucket, tokenizer_key, "local_model/tokenizer.json")
s3.download_file(bucket, config_key, "local_model/config.json")

print("Finished download of s3 files")

# Deploy
model_dir = local_dir
deployment = PredictDeployment.bind(model_id=model_dir)
serve.run(deployment)