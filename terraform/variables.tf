variable "aws_region" {
  description = "AWS Region."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC to be created."
  type        = string
  default     = "10.8.0.0/16"
}

variable "db_private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Airflow DB."
  type        = list(string)
  default     = ["10.8.51.0/26", "10.8.52.0/26"]
}

variable "name" {
  description = "Name to be added to the modules and resources."
  type        = string
  default     = "gen-ai-eks-new"
}

variable "cluster_version" {
  description = "Amazon EKS Cluster version."
  type        = string
  default     = "1.27"
}

variable "jupyter_hub_values_path" {
  description = "Path for JupyterHub Helm values file."
  type        = string
  default     = "helm-values/jupyterhub-profiles-values.yaml"
}

variable "kuberay_cluster_train_values_path" {
  description = "Path for KubeRay Helm values file."
  type        = string
  default     = "helm-values/kuberay-cluster-values-train.yaml"
}

# NVIDIA Operator

variable "nvidia_gpu_values_path" {
  description = "Path for NVidia GPU operator Helm values file."
  type        = string
  default     = "helm-values/gpu-operator-values-ubuntu.yaml"
}

# Apache Airflow needs

variable "airflow_name" {
  description = "Apache AirFlow name."
  type        = string
  default     = "airflow"
}

variable "apache_airflow_values_path" {
  description = "Path for Apache Airflow Helm values file."
  type        = string
  default     = "helm-values/airflow-values.yaml"
}