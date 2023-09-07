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
