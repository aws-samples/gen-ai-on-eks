# ML-OPS on Amazon EKS

Goal is to provide a platform that can support distributed ML systems.

<!-- Reference from Instacart blog: https://tech.instacart.com/distributed-machine-learning-at-instacart-4b11d7569423 -->

Scalability: We must be able to scale a large number of distributed ML workloads on both CPU and GPU instances with a robust system that maintains high performance and reliability. **We are going to achieve that using Karpenter.**

Resource Efficiency: We aim to fully utilize distributed computation resources to maximize system throughput and achieve the fastest execution at optimal cost.

Diversity: The selected computation framework should be as extensible as possible to support diverse distributed ML paradigms. In addition, we should be able to handle diverse environments that are specific to different ML workloads.

## Pre Reqs
- Terraform
- Spot Linked Role

```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

## Architecture Diagram

![ML Ops Arch Diagram](static/ml-ops-arch-diagram.png)

## Spin-up environment

Open [terraform](terraform/) folder, change the desired variables on [vars.tf](terraform/vars.tf) and execute the following command:

```bash
terraform apply --auto-approve
```

This will provision a EKS cluster with pre-installed add-ons using [Amazon EKS Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons), it will also install Jupyterhub for development and analysis with a mounted EFS file system, kuberay-operator to managed Ray clusters using CRDs, and Apache Airflow (TBD) connected to a Git repository in order to pull the Dags.

- [Ray Docs](./kuberay-operator/README.md)
- [JupyterHub Docs](./jupyter-hub/README.md)
