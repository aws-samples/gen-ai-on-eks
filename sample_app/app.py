import gradio as gr
import requests

# Constants for model endpoints
FINETUNED_ENDPOINT = "/falcon_finetuned_financial"
NON_FINETUNED_ENDPOINT = "/falcon_non_finetuned"

# Function to generate text
def text_generation(model_choice, message, history):
    # Select the appropriate model endpoint based on user choice
    if model_choice == "Falcon Financial":
        model_endpoint = FINETUNED_ENDPOINT
    else:
        model_endpoint = NON_FINETUNED_ENDPOINT

    ray_address = f"http://localhost:8000{model_endpoint}"

    prompt = message
    sample_input = {
        "prompt": prompt,
        "params": {
            "temperature": 0.7,
            "top_p": 0.9,
            "max_tokens": 256,
            "num_beams": 4,
        },
    }

    output_response = requests.post(ray_address, json=sample_input, timeout=60)
    full_output = output_response.text

    # Removing the original question from the output
    answer_only = full_output.replace(prompt, "", 1).strip()

    # Remove duplicate lines
    lines = answer_only.split("\n")
    unique_lines = list(set(lines))
    unique_answer_only = "\n".join(unique_lines)

    return unique_answer_only


# Define the Gradio interface
iface = gr.Interface(
    fn=text_generation,
    inputs=[
        gr.inputs.Dropdown(
            choices=["Falcon Financial", "Falcon Default"],
            label="Model Choice",
        ),
        gr.inputs.Textbox(lines=5, label="Your Message"),
        gr.inputs.Textbox(lines=5, label="History", optional=True),
    ],
    outputs="text",
    live=False,  # Set this to False
)

# Launch the interface
iface.launch()
