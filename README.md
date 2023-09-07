# Fine-tuning Foundation Models on Amazon EKS for AI/ML Workloads

This project aims to showcase the power of Amazon EKS for AI/ML tasks, specifically for fine-tuning Foundation Models like GPTJ. Utilizing a single Amazon EKS cluster, we run two separate Ray clusters for training and serving tasks, all managed by the Ray Operator. This project leverages additional tools like Karpenter for auto-scaling and JupyterHub for code development and data analysis.

> **Inspiration**: [Distributed Machine Learning at Instacart](https://tech.instacart.com/distributed-machine-learning-at-instacart-4b11d7569423)

## Features

- **Rapid Experimentation**: Develop and test training and serving scripts via Jupyter Notebook instances provisioned by JupyterHub.
- **Scalability**: Efficiently scale numerous distributed ML workloads on both CPU and GPU instances using Karpenter.
- **Resource Efficiency**: Maximize system throughput by fully utilizing distributed computation resources.
- **Diverse Environment Support**: Extensible computation framework capable of supporting various ML paradigms and workloads.

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

### Single EKS Cluster with Dual Ray Clusters

This demonstration utilizes a single EKS cluster to manage two distinct Ray clusters for training and serving, powered by the Ray Operator. Each Ray cluster has its own Karpenter provisioner, enabling us to tailor the compute resources for each workload effectively.

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
- **Ray Operator**: To manage Ray clusters
- **Karpenter**: For automatic scaling
- **Kube Prometheus Stack**: For observability
- **Apache Airflow**: To automate the e2e ML pipeline, fetching DAGs from this Git repository

### Update Kubeconfig

```bash
aws eks update-kubeconfig --region $AWS_REGION --name fmops-cluster
```

### Validate Cluster Setup

```bash
kubectl get nodes
```

You should see output similar to:

```
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-8-11-154.us-west-2.compute.internal   Ready    <none>   21d     v1.27.3-eks-a5565ad
ip-10-8-20-67.us-west-2.compute.internal    Ready    <none>   2d22h   v1.27.4-eks-8ccc7ba
ip-10-8-22-144.us-west-2.compute.internal   Ready    <none>   60m     v1.27.3
ip-10-8-23-25.us-west-2.compute.internal    Ready    <none>   67m     v1.27.3
ip-10-8-23-84.us-west-2.compute.internal    Ready    <none>   70m     v1.27.3
ip-10-8-24-190.us-west-2.compute.internal   Ready    <none>   67m     v1.27.3
ip-10-8-26-250.us-west-2.compute.internal   Ready    <none>   70m     v1.27.3
ip-10-8-26-80.us-west-2.compute.internal    Ready    <none>   67m     v1.27.3
ip-10-8-29-105.us-west-2.compute.internal   Ready    <none>   21d     v1.27.3-eks-a5565ad
```

You're now ready to proceed with the demonstration.

## Modules in This Demonstration

The demonstration is broken down into several key modules, each focusing on a specific aspect of fine-tuning Foundation Models like GPTJ on Amazon EKS. By the end of this demonstration, you'll have an end-to-end example showcasing the versatility and power of EKS for AI/ML workloads.

### 1. Serving a Non Fine-Tuned Model with Ray

In this module, you'll learn how to deploy a generic, non-fine-tuned GPTJ model using Ray Serve. This sets the stage for comparison with a fine-tuned model later in the demo.

### 2. Crafting the Training Script in Jupyter Notebook

This module covers how to create a Jupyter Notebook that encapsulates the training script you'll use for fine-tuning the GPTJ model. We focus on integrating contextual data into the model, setting up the environment for rapid experimentation.

### 3. Initiating Training via RayJobSubmission

Once the training script is ready, you'll use the Ray Job Submission API to kick off the training process. This module covers the entire process, from job configuration to actual submission.

### 4. On-Demand Node Scaling with Karpenter

Here, we dive into how Karpenter dynamically scales the EKS cluster's nodes based on workload requirements. This includes real-time scaling to handle the demands of the fine-tuning process.

### 5. Monitoring GPU Utilization in the Ray Dashboard

In this module, we'll explore the Ray Dashboard, focusing on how to monitor GPU utilization. Understanding resource usage is crucial for optimizing machine learning workloads.

### 6. Creating the Serving Script for the Fine-Tuned Model in Jupyter Notebook

Once the model is fine-tuned, you'll create another Jupyter Notebook to house the serving script. This script will handle the deployment of your fine-tuned GPTJ model using Ray Serve.

### 7. Serving the Fine-Tuned Model

Finally, you'll learn how to use the serving script to deploy the fine-tuned model, offering insights into its performance and advantages over the non-fine-tuned version. We'll also discuss how to route traffic to the fine-tuned model and perform any necessary optimizations.