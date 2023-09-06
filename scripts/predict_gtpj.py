import json
import requests


import requests

prompt = (
    "I love each"
)

ray_adress = "http://localhost:8000/"
sample_input = {"text": prompt}

output = requests.post(ray_adress, json=[sample_input]).json()
print(output)