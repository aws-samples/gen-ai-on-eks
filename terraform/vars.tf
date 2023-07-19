variable "vpc_cidr" {
  default = "10.8.0.0/16"
}

variable "name" {
  default = "fmops-cluster"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_version" {
  default = "1.27"
}

# Helm values to apply when deploying JupyterHub Helm Chart

variable "jupyter_karpenter_config" {
  default = "../jupyter-hub/karpenter-provisioner-jupyter-hub.yaml"
}

variable "jupyter_karpenter_config_node_template" {
  default = "../jupyter-hub/karpenter-aws-node-template-jupyter-hub.yaml"
}

variable "jupyter_hub_values_path" {
  default = "../jupyter-hub/config.yaml"
}

variable "raycluster_karpenter_config" {
  default = "../kuberay-operator/karpenter-provisioner-ray-operator.yaml"
}

variable "raycluster_karpenter_config_node_template" {
  default = "../kuberay-operator/karpenter-aws-node-template-ray-operator.yaml"
}

variable "kuberay_cluster_values_path" {
  default = "../kuberay-operator/values.yaml"
}