# FMOps on Amazon EKS

Goal is to provide a platform that can support distributed ML systems.

<!-- Copied from Instacart blog: https://tech.instacart.com/distributed-machine-learning-at-instacart-4b11d7569423 -->

Scalability: We must be able to scale a large number of distributed ML workloads on both CPU and GPU instances with a robust system that maintains high performance and reliability. **We are going to achieve that using Karpenter.**

Resource Efficiency: We aim to fully utilize distributed computation resources to maximize system throughput and achieve the fastest execution at optimal cost.

Diversity: The selected computation framework should be as extensible as possible to support diverse distributed ML paradigms. In addition, we should be able to handle diverse environments that are specific to different ML workloads.

## Pre Reqs
- Terraform

# Spin-up environment

Open [terraform](terraform/) folder, change the desired variables on [vars.tf](terraform/vars.tf)
```bash
```
