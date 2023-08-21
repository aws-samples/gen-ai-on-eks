import json
import requests

sample_request_input = {
    "Pregnancies": 0,
    "Glucose": 100,
    "Blood Pressure": 72,
    "SkinThickness": 35,
    "Insulin": 0,
    "BMI": 33.6,
    "Diabetes Pedigree": 0.625,
    "Age": 25,
}

response = requests.post(
    "http://localhost:8000/", json=[sample_request_input]
).json()

print(response)
