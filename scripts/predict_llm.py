import requests

sample_request_input = {
    "Pregnancies": 6,
    "Glucose": 148,
    "BloodPressure": 72,
    "SkinThickness": 35,
    "Insulin": 0,
    "BMI": 33.6,
    "DiabetesPedigree": 0.625,
    "Age": 50,
}

response = requests.get(
    "http://localhost:8000/regressor", json=sample_request_input
)

print(response.text)
