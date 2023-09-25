# Fine-tuning Foundation Models on Amazon EKS for AI/ML Workloads

This demonstration showcases the flexibility of a single EKS (Elastic Kubernetes Service) cluster in managing diverse Ray workloads through multiple Ray clusters, orchestrated by the Ray Operator. One Ray cluster is pre-deployed specifically for training tasks, utilizing the RayJobSubmission API for streamlined job management. Additional Ray clusters can be dynamically spun up on-demand for various other workloads like serving, simulation, or data processing.

To further optimize resource allocation for these distinct workloads, each Ray cluster is equipped with its own Karpenter provisioner. This allows us to fine-tune the compute resources that are dedicated to each Ray cluster, ensuring efficiency and cost-effectiveness.

## Prerequisites

- AWS Credentials configured
- AWS CLI
- kubectl
- Helm
- Terraform
- Spot Instance Linked Role

### Create Spot Instance Linked Role

```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

## Architecture

![ML Ops Arch Diagram](static/ml-ops-arch-diagram.png)

## Environment Setup

### Initialize Global Variables

```bash
export TERRAFORM_STATE_BUCKET="<DEFINE A NAME FOR YOUR STATE BUCKET>"
export AWS_REGION="<DEFINE YOUR AWS REGION>"
```

### Create S3 Bucket for Terraform State

```bash
aws s3 mb s3://$TERRAFORM_STATE_BUCKET --region $AWS_REGION
```

### Update Terraform Configuration Files

Navigate to the [`terraform/`](terraform/) directory and update `providers.tf` and `vars.tf`:

#### `providers.tf`

```hcl
terraform {
  backend "s3" {
    bucket = "TERRAFORM_STATE_BUCKET" # REPLACE HERE
    key    = "fm-ops-demo/fm-ops-demo.json"
    region = "AWS_REGION"              # REPLACE HERE
  }
}

provider "aws" {
  region = "AWS_REGION"               # REPLACE HERE
}
```

#### `vars.tf`

```hcl
variable "aws_region" {
  default = "AWS_REGION"              # REPLACE HERE
}
```

### Apply Terraform Script

```bash
terraform apply --auto-approve
```

This command provisions an EKS cluster along with the following components:

- **JupyterHub**: For development and analysis
- **Nvidia GPU Operator**: The GPU Operator allows administrators of Kubernetes clusters to manage GPU nodes just like CPU nodes in the cluster, instead of provisioning a special OS image.
- **Ray Operator**: To manage Ray clusters
- **Karpenter**: For automatic scaling
- **Kube Prometheus Stack**: For observability
- **Apache Airflow**: To automate the e2e ML pipeline, fetching DAGs from this Git repository

### Exporting terraform outputs

Since we will be pushing code to Amazon S3 let's export the `BUCKET_NAME`

```bash
export BUCKET_NAME=$(terraform output -raw bucket_name)
```

> Have this bucket name handy, we will use it troughout the demo

### Update Kubeconfig

```bash
aws eks update-kubeconfig --region $AWS_REGION --name fmops-cluster
```

### Validate Cluster Setup

```bash
kubectl get nodes
```

You should see output similar to:

```bash
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-8-11-154.us-west-2.compute.internal   Ready    <none>   21d     v1.27.3-eks-a5565ad
ip-10-8-20-67.us-west-2.compute.internal    Ready    <none>   2d22h   v1.27.4-eks-8ccc7ba
ip-10-8-22-144.us-west-2.compute.internal   Ready    <none>   60m     v1.27.3
ip-10-8-23-25.us-west-2.compute.internal    Ready    <none>   67m     v1.27.3
ip-10-8-23-84.us-west-2.compute.internal    Ready    <none>   70m     v1.27.3
... additional nodes
```

You're now ready to proceed with the demonstration.

## Modules in This Demonstration

The demonstration is broken down into two modules, each focusing on a specific aspect of fine-tuning Foundation Models like Falcon 7B on Amazon EKS. By the end of this demonstration, you'll have learned how to use Notebooks powered by JupyterHub to craft your training and serving script and run them on specific Ray Clusters.

### [1. Crafting training and serving script in Jupyter Notebook and training using Ray](./modules/1-crafting-serving-training-notebook.md)
### [2. Serving finetuned model with contextual data using RayOperator](./modules/2-serving-finetuned-model.md)