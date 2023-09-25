import gradio as gr
import requests
import os

model_endpoint = os.getenv("MODEL_ENDPOINT")
ray_address = f"http://localhost:8000{model_endpoint}"

def text_generation(message, history):
    prompt = message
    sample_input = {
        "prompt": prompt,
        "params": {
            "temperature": 0.7,
            "top_p": 0.9,
            "max_tokens": 256,
            "num_beams": 4
        }
    }

    output_response = requests.post(ray_address, json=sample_input, timeout=60)
    full_output = output_response.text  # Getting the full output as a string

    # Removing the original question from the output
    answer_only = full_output.replace(prompt, '', 1).strip()  # The '1' indicates to only replace the first occurrence

    return answer_only

gr.ChatInterface(text_generation).launch()
