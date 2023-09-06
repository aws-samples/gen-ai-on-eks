import gradio as gr
import requests

ray_adress = "http://localhost:8000/"

def text_generation(message, history):
    
    prompt = (message)
    sample_input = {"text": prompt}
    output = requests.post(ray_adress, json=[sample_input]).json()
    parsed_output = (output[0].get("responses")).split("<|endoftext|>")
    message = parsed_output[0]
    return message

gr.ChatInterface(text_generation).launch()
