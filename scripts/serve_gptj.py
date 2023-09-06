import os
import ray
import boto3
from ray import serve
from ray.serve.http_adapters import pandas_read_json
from ray.train.huggingface import TransformersPredictor
from transformers import AutoModelForCausalLM, AutoTokenizer

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
            "deepspeed==0.9.2",
        ]
    }
)

serve.start(detached=True)

s3 = boto3.client("s3")
bucket = "fm-ops-datasets"
model_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/pytorch_model.bin"
tokenizer_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/tokenizer.json"
config_json_key = "checkpoints/TransformersTrainer_2023-09-05_12-25-24/TransformersTrainer_f638a_00000_0_2023-09-05_12-25-24/checkpoint_000000/config.json"

if __name__ == "__main__":
    os.makedirs("local_model", exist_ok=True)
    # Download model and tokenizer from S3 to local storage
    s3.download_file(bucket, model_key, "local_model/pytorch_model.bin")
    s3.download_file(bucket, tokenizer_key, "local_model/tokenizer.json")
    s3.download_file(bucket, config_json_key, "local_model/config.json")
    
    # Load tokenizer and model
    tokenizer = AutoTokenizer.from_pretrained("local_model")
    model = AutoModelForCausalLM.from_pretrained("local_model").cuda()  # Move model to GPU
    
    # Create predictor
    predictor = TransformersPredictor(model, tokenizer)
    
    # Deployment options to use a GPU
    deployment_options = {
        "num_replicas": 1,
        "resources_per_replica": {"GPU": 1}
    }
    
    # Deploy model with Ray Serve
    serve.create_deployment(
        name="TransformersService", 
        version="1.0",
        route_prefix="/gptj", 
        http_adapter=pandas_read_json
    ).set_predictor(
        predictor
    )

