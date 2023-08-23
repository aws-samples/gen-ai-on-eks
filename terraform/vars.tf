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

variable "jupyter_hub_values_path" {
  default = "helm-values/jupyterhub-values.yaml"
}

variable "kuberay_cluster_values_path" {
  default = "helm-values/kuberay-cluster-values.yaml"
}

# NVIDIA Operator

variable "nvidia_gpu_values_path" {
  default = "helm-values/gpu-operator-values-ubuntu.yaml"
}

# Apache Airflow needs

variable "airflow_name" {
  default = "airflow"
}

variable "apache_airflow_values_path" {
  default = "helm-values/airflow-values.yaml"
}