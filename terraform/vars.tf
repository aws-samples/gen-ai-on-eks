variable "vpc_cidr" {
  default = "10.8.0.0/16"
}

variable "db_private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Airflow DB."
  default     = ["10.8.51.0/26", "10.8.52.0/26"]
  type        = list(string)
}

variable "name" {
  default = "fmops-cluster"
}

variable "aws_region" {
  default = "us-west-2"
}

variable "cluster_version" {
  default = "1.27"
}

# Karpenter provisioner default

variable "karpenter_default_provisioner" {
  default = "../karpenter-provisioners/default-karpenter-provisioner.yaml"
}

variable "karpenter_default_node_template" {
  default = "../karpenter-provisioners/default-karpenter-node-template.yaml"
}

# Helm values to apply when deploying JupyterHub Helm Chart

variable "jupyter_karpenter_config" {
  default = "../karpenter-provisioners/karpenter-provisioner-gpu.yaml"
}

variable "jupyter_karpenter_config_node_template" {
  default = "../karpenter-provisioners/karpenter-aws-node-template-gpu.yaml"
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

# NVIDIA Operator

variable "nvidia_gpu_values_path" {
  default = "../nvidia-gpu-operator/values.yaml"
}

# Apache Airflow needs

variable "airflow_name" {
  default = "airflow"
}

variable "apache_airflow_values_path" {
  default = "../apache-airflow/values.yaml"
}