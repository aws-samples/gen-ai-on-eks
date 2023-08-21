import pickle
import ray
from ray import serve

ray.init(address="auto", namespace="serve")


@serve.deployment(num_replicas=2, route_prefix="/predict")
class XGB:
    def __init__(self):
        with open("model.pkl", "rb") as f:
            self.model = pickle.load(f)

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


serve.start(detached=True)
XGB.deploy()
