import ray
import boto3
import pickle
from ray.train.xgboost import XGBoostPredictor
from ray import serve
from ray.serve import PredictorDeployment
from ray.serve.http_adapters import pandas_read_json

ray.init(address="auto", namespace="serve")
serve.start(detached=True)

s3 = boto3.client("s3")
bucket = "fm-ops-datasets"
prefix = "model"

if __name__ == "__main__":
    response = s3.get_object(Bucket=bucket, Key=f"{prefix}/model.pkl")
    pickle_data = response["Body"].read()
    model = pickle.loads(pickle_data)

    serve.run(
        PredictorDeployment.options(name="XGBoostService").bind(
            XGBoostPredictor, model, http_adapter=pandas_read_json
        )
    )
