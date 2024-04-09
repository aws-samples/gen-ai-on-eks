variable "aws_region" {
  description = "AWS Region."
  type        = string
  default     = null
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/21"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}


variable "name" {
  description = "Name to be added to the modules and resources."
  type        = string
  default     = "gen-ai-eks"
}

variable "cluster_version" {
  description = "Amazon EKS Cluster version."
  type        = string
  default     = "1.29"
}


variable "enable_aws_efa_k8s_device_plugin" {
  description = "Enable AWS EFA K8s Device Plugin"
  type        = bool
  default     = false
}

variable "huggingface_token" {
  description = "Hugging Face Secret Token"
  type        = string
  sensitive   = true
}
