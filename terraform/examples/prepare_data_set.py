import json
import boto3

# Preparing the data set
def preprocess_intents_json(intents_file):
    with open(intents_file, "r") as f:
        data = json.load(f)
    
    preprocessed_data = []
    
    for intent in data["intents"]:
        for pattern in intent["patterns"]:
            preprocessed_data.append(f"User: {pattern}\n")
            for response in intent["responses"]:
                preprocessed_data.append(f"Assistant: {response}\n")
    
    return "".join(preprocessed_data)

# Save data set to a file
def save_preprocessed_data(preprocessed_data, output_file):
    with open(output_file, "w") as f:
        f.write(preprocessed_data)


def write_file_to_s3(bucket_name, file_name, local_file_path):
    try:
        s3_client = boto3.client('s3')

        # Upload the file to the S3 bucket
        s3_client.upload_file(local_file_path, bucket_name, file_name)

        print(f"File '{file_name}' uploaded successfully to S3 bucket '{bucket_name}'.")

    except Exception as e:
        print(f"Error: {str(e)}")


def download_file_from_s3(bucket_name, s3_file_name, local_file_name):
    try:
        s3_client = boto3.client('s3')

        # Download the file from the S3 bucket
        local_file_path = f"{local_file_name}"
        s3_client.download_file(bucket_name, s3_file_name, local_file_path)

        print(f"File '{s3_file_name}' downloaded successfully to '{local_file_path}'.")

    except Exception as e:
        print(f"Error: {str(e)}")

def main():
    output_file = "mental_health_data.txt"
    bucket_name = "testing-fine-tuning-jakhs"
    s3_file_name = "input/intents.json"
    local_file_name = "intents.json"
    
    download_file_from_s3(bucket_name, s3_file_name, local_file_name)

    preprocessed_data = preprocess_intents_json(local_file_name)
    save_preprocessed_data(preprocessed_data, output_file)
    write_file_to_s3(bucket_name, f'output/{output_file}', output_file)

if __name__ == "__main__":
    main()