################################################################################
# Karpenter Needed resources and permissions
################################################################################

# We have to augment default the karpenter node IAM policy with
# permissions we need for Ray Jobs to run until IRSA is added
# upstream in kuberay-operator. See issue
# https://github.com/ray-project/kuberay/issues/746
module "karpenter_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 5.20"

  name        = "KarpenterS3ReadWritePolicy"
  description = "IAM Policy to allow read and write in a S3 bucket for karpenter nodes"

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListObjectsInBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["*"]
        },
        {
          Sid      = "AllObjectActions"
          Effect   = "Allow"
          Action   = "s3:*Object"
          Resource = ["*"]
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "karpenter_attach_policy_to_role" {
  role       = element(split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn), 1)
  policy_arn = module.karpenter_policy.arn
}

# Bucket to persist training data and output model
resource "aws_s3_bucket" "fm_ops_data" {
  bucket_prefix = "datasets-checkpoints"

  tags = {
    Name = "datasets-checkpoints"
  }
}

################################################################################
# EKS Blueprints add-ons
################################################################################
module "eks_blueprints_addons" {
  source            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=v1.2.2"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_efs_csi_driver           = true # Will be used for Jupyter Notebooks and DAG on Apache Airflow
  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  karpenter_enable_spot_termination = true
  enable_metrics_server             = true
  enable_kube_prometheus_stack      = true

  helm_releases = {
    gpu-operator = {
      description      = "A Helm chart for NVIDIA GPU operator"
      namespace        = "gpu-operator"
      create_namespace = true
      chart            = "gpu-operator"
      chart_version    = "v23.3.2"
      repository       = "https://helm.ngc.nvidia.com/nvidia"
      values           = [file(var.nvidia_gpu_values_path)]
    }
    jupyter-hub = {
      description      = "A Helm chart for JupyterHub"
      namespace        = "jupyterhub"
      create_namespace = false
      chart            = "jupyterhub"
      chart_version    = "2.0.0"
      repository       = "https://jupyterhub.github.io/helm-chart/"
      values = [templatefile(var.jupyter_hub_values_path, {
        jupyter_single_user_sa_name = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      })]
    }
    ray-operator = {
      description      = "A Helm chart for RAY operator"
      namespace        = "kuberay-operator"
      create_namespace = true
      chart            = "kuberay-operator"
      chart_version    = "0.6.0"
      repository       = "https://ray-project.github.io/kuberay-helm/"
    }
    ray-cluster-train = {
      description      = "A Helm chart for RAY operator"
      namespace        = "ray-cluster-train"
      create_namespace = true
      chart            = "ray-cluster"
      chart_version    = "0.5.0"
      repository       = "https://ray-project.github.io/kuberay-helm/"
      values           = [file(var.kuberay_cluster_train_values_path)]
    }
    # apache-airflow = {
    #   description      = "A Helm chart for Apache Airflow"
    #   namespace        = kubernetes_namespace_v1.airflow.metadata[0].name
    #   create_namespace = false
    #   chart            = "airflow"
    #   chart_version    = "1.9.0"
    #   repository       = "https://airflow.apache.org"
    #   values = [templatefile(var.apache_airflow_values_path, {
    #     airflow_version       = "2.6.3"
    #     airflow_db_user       = var.airflow_name
    #     airflow_db_pass       = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
    #     airflow_db_host       = try(element(split(":", module.db.db_instance_endpoint), 0), "")
    #     airflow_db_name       = try(module.db.db_instance_name, "")
    #     webserver_secret_name = "airflow-webserver-secret-key"

    #     airflow_workers_service_account_name   = kubernetes_service_account_v1.airflow_worker.metadata[0].name
    #     airflow_scheduler_service_account_name = kubernetes_service_account_v1.airflow_scheduler.metadata[0].name
    #     webserver_service_account_name         = kubernetes_service_account_v1.airflow_webserver.metadata[0].name
    #     s3_bucket_name                         = try(module.airflow_s3_bucket.s3_bucket_id, "")
    #     efs_pvc                                = "airflowdags-pvc"
    #   })]
    # }
    karpenter-resources-default = {
      name        = "karpenter-resources-default"
      description = "A Helm chart for karpenter CPU based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          clusterName: ${module.eks.cluster_name}
          taints: []
          labels: []
        EOT
      ]
    }
    karpenter-resources-cpu = {
      name        = "karpenter-resources-cpu"
      description = "A Helm chart for karpenter CPU based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: default-jupyter
          clusterName: ${module.eks.cluster_name}
        EOT
      ]
    }
    karpenter-resources-ts = {
      name        = "karpenter-resources-ts"
      description = "A Helm chart for karpenter GPU based resources - compatible with GPU time slicing"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: gpu-ts
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["xlarge", "2xlarge", "4xlarge", "8xlarge", "16xlarge", "24xlarge"]
          instanceFamilies: ["g5"]
          deviceName: /dev/sda1
          taints:
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
    karpenter-resources-mig = {
      name        = "karpenter-resources-mig"
      description = "A Helm chart for karpenter GPU based resources - compatible with GPU MIG"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: gpu-mig
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["24xlarge"]
          instanceFamilies: ["p4d"]
          deviceName: /dev/sda1
          taints:
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
    karpenter-resources-inf = {
      name        = "karpenter-resources-inf"
      description = "A Helm chart for karpenter Inferentia based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: inferentia
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["8xlarge", "24xlarge"]
          instanceFamilies: ["inf2"]
          taints:
            - key: aws.amazon.com/neuroncore
              value: "true"
              effect: "NoSchedule"
            - key: aws.amazon.com/neuron
              value: "true"
              effect: "NoSchedule"
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
        EOT
      ]
    }
    karpenter-resources-trn = {
      name        = "karpenter-resources-trn"
      description = "A Helm chart for karpenter Trainium based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: trainium
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["2xlarge", "32xlarge"]
          instanceFamilies: ["inf2"]
          taints:
            - key: aws.amazon.com/neuroncore
              value: "true"
              effect: "NoSchedule"
            - key: aws.amazon.com/neuron
              value: "true"
              effect: "NoSchedule"
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
        EOT
      ]
    }
    karpenter-resources-ray-serve = {
      name        = "karpenter-resources-ray-serve"
      description = "A Helm chart for karpenter ray serve based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: gpu-serve-ray
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["xlarge", "2xlarge", "4xlarge", "8xlarge", "16xlarge", "24xlarge"]
          instanceFamilies: ["g5"]
          deviceName: /dev/sda1
          labels: []
          taints:
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
    karpenter-resources-ray-train = {
      name        = "karpenter-resources-ray-train"
      description = "A Helm chart for karpenter Trainium based resources"
      chart       = "${path.module}/helm-values/karpenter-resources"
      values = [
        <<-EOT
          name: gpu-train-ray
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["2xlarge", "4xlarge"]
          instanceFamilies: ["g5"]
          deviceName: /dev/sda1
          labels: []
          taints:
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
  }

  tags = local.tags

}
