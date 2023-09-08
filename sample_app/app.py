import gradio as gr
import requests
import os

model_endpoint = os.getenv("MODEL_ENDPOINT") 
ray_adress = f"http://localhost:8000{model_endpoint}"

def text_generation(message, history):
    
    prompt = (message)
    sample_input = {"text": prompt}
    output = requests.post(ray_adress, json=[sample_input]).json()
    print(output)
    parsed_output = (output[0].get("responses")).split("<|endoftext|>")
    message = parsed_output[0]
    return message

gr.ChatInterface(text_generation).launch()
