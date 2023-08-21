import pickle
import ray
from ray import serve
import boto3

ray.init(address="auto", namespace="serve")
serve.start(detached=True)

s3 = boto3.client("s3")
bucket = "fm-ops-datasets"
prefix = "model"


@serve.deployment(num_replicas=2, route_prefix="/predict")
class XGB:
    def __init__(self, model):
        self.model = model

    async def __call__(self, starlette_request):
        payload = await starlette_request.json()
        print("Worker: received starlette request with data", payload)

        input_vector = [
            payload["Pregnancies"],
            payload["Glucose"],
            payload["Blood Pressure"],
            payload["Skin Thickness"],
            payload["Insulin"],
            payload["BMI"],
            payload["DiabetesPedigree"],
            payload["Age"],
        ]

        prediction = self.model.predict([input_vector])[0]

        return {"result": prediction}


if __name__ == "__main__":
    response = s3.get_object(Bucket=bucket, Key=f"{prefix}/model.pkl")
    pickle_data = response["Body"].read()
    model = pickle.loads(pickle_data)

    serve.run(XGB.bind(model))
