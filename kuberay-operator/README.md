# KubeRay Operator on EKS

Ray is an open-source unified compute framework that makes it easy to scale AI and Python workloads — from reinforcement learning to deep learning to tuning, and model serving. Learn more about Ray’s rich set of libraries and integrations.

## Install operator on Amazon EKS using Helm Charts

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator --namespace kuberay --version 0.5.0 --create-namespace
```

## Access Ray Dashboard locally using kubectl port-forward

```bash
kubectl --namespace=kuberay-operator port-forward service/raycluster-kuberay-head-svc 8265:8265
```