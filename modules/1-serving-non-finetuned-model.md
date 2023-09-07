## Module: Deploying a Non Fine-Tuned Model with Ray and Amazon S3

### Objective

In this module, we will walk through the steps required to deploy a Ray service that utilizes a non fine-tuned model. The code for this model will be zipped and uploaded to an Amazon S3 bucket. Subsequently, we will deploy a Ray service in a Kubernetes cluster, configured to pull this code using a pre-signed URL.

### Create Zip File from Training Code and Upload to Amazon S3

#### Step 1: Create the ZIP File

**Objective**: To package our model's serving script for uploading to Amazon S3.

1. **Navigate to the root directory**:
```bash
cd scripts/
```

2. **Create a ZIP file** containing the serving script:
```bash
zip 00_serve_gptj_non_finetuned.zip 00_serve_gptj_non_finetuned.py
```

#### Step 2: Upload the ZIP File to Amazon S3

**Objective**: To upload the packaged model script to a secure S3 bucket.

Execute the following command to upload the ZIP file to your designated S3 bucket:

```bash
aws s3 cp 00_serve_gptj_non_finetuned.zip s3://$BUCKET_NAME/
```

#### Step 3: Generate a Pre-Signed URL for the ZIP File

**Objective**: To generate a secure, time-limited URL for accessing the uploaded ZIP file.

Generate a pre-signed URL that will expire in 1 hour:

```bash
export PRESIGNED_URL=$(aws s3 presign s3://$BUCKET_NAME/00_serve_gptj_non_finetuned.zip --expires-in 3600)
```

### Deploy RayService to Kubernetes Cluster

#### Step 1: Update the `working_dir` in RayService Manifest

**Objective**: To provide the Ray service with the location from which it should fetch the serving script.

1. Navigate to the directory containing Ray manifests:

```bash
cd ../ray_serve_manifests
```

2. Update the `working_dir` using `envsubst` command that is compatible with both macOS and Linux:

```bash
envsubst < 00_ray_serve_non_fine_tuned.yaml.template > 00_ray_serve_non_fine_tuned.yaml
```

#### Step 2: Deploy the RayService

Apply the updated YAML manifest to deploy the Ray service:

```bash
kubectl apply -f 00_ray_serve_non_fine_tuned.yaml
```

### Verify Deployment

After applying the manifest, you can verify the status of the RayService, and explore its corresponding resources:

1. **Check the RayService**:
```bash
kubectl get rayservices -n ray-svc-non-finetuned
```

2. **Check the Pods**:
```bash
kubectl get pods -n ray-svc-non-finetuned
```

3. **Check the Node Provisioning**:
```bash
kubectl get nodes -l provisioner=gpu-serve
```

4. **Check NVIDIA GPU Operator**:
```bash
kubectl get po -n gpu-operator
```

5. **Wait for Resources to Initialize**:
```bash
kubectl get po -n ray-svc-non-finetuned -w
```

> It can take a while to initialize because of the dependencies (GPU Operator and pulling Ray Images)

### Verify if the application is already being served:

Let's start by using port-forward to get access to Ray Dashboard:

```bash
kubectl port-forward svc/$(kubectl get svc -nray-svc-non-finetuned | grep -i ray-svc | awk '{print $1}') 8265:8265 -n ray-svc-non-finetuned
```


