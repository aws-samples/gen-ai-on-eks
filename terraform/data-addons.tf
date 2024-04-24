#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.31.5" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm-values/jupyterhub-values.yaml",
      { jupyter_single_user_sa_name = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
    })]
    version          = "3.3.7"
    namespace        = kubernetes_namespace_v1.jupyterhub.id
    create_namespace = false
  }


  enable_volcano = false
  #---------------------------------------
  # Kuberay Operator
  #---------------------------------------
  enable_kuberay_operator = true
  kuberay_operator_helm_config = {
    version = "1.1.0"
    # Enabling Volcano as Batch scheduler for KubeRay Operator
    values = [
      <<-EOT
      batchScheduler:
        enabled: false
    EOT
    ]
  }

  #---------------------------------------------------------------
  # NVIDIA Device Plugin Add-on
  #---------------------------------------------------------------
  enable_nvidia_device_plugin = true
  nvidia_device_plugin_helm_config = {
    version = "v0.14.5"
    name    = "nvidia-device-plugin"
    values = [
      <<-EOT
        gfd:
          enabled: true
        nfd:
          worker:
            tolerations:
              - key: nvidia.com/gpu
                operator: Exists
                effect: NoSchedule
              - operator: "Exists"
      EOT
    ]
  }

  #---------------------------------------
  # EFA Device Plugin Add-on
  #---------------------------------------
  # IMPORTANT: Enable EFA only on nodes with EFA devices attached.
  # Otherwise, you'll encounter the "No devices found..." error. Restart the pod after attaching an EFA device, or use a node selector to prevent incompatible scheduling.
  enable_aws_efa_k8s_device_plugin = var.enable_aws_efa_k8s_device_plugin
  aws_efa_k8s_device_plugin_helm_config = {
    values = [file("${path.module}/helm-values/aws-efa-k8s-device-plugin-values.yaml")]
  }

  #---------------------------------------------------------------
  # Karpenter Resources Add-on
  #---------------------------------------------------------------
  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    gpu-karpenter = {
      values = [
        <<-EOT
      name: gpu-karpenter
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[2]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        amiSelectorTerms:
        - id: ami-096399a9e3c152f3b
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: gpu-karpenter
        taints:
          - key: nvidia.com/gpu
            value: "Exists"
            effect: "NoSchedule"
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["g5"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: [ "4xlarge", "8xlarge","12xlarge"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 180s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
    x86-cpu-karpenter = {
      values = [
        <<-EOT
      name: x86-cpu-karpenter
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[3]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
        blockDeviceMappings:
          - deviceName: /dev/xvda
            ebs:
              volumeSize: 240Gi
              volumeType: gp3
              iops: 10000
              encrypted: true
              deleteOnTermination: true

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: x86-cpu-karpenter
        requirements:
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r","c","m"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: [ "xlarge", "2xlarge", "4xlarge", "8xlarge", "16xlarge", "24xlarge"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 180s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
  }

  depends_on = [
    kubernetes_secret_v1.huggingface_token,
    kubernetes_config_map_v1.notebook
  ]
}

#---------------------------------------------------------------
# Additional Resources
#---------------------------------------------------------------

resource "kubernetes_namespace_v1" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}


resource "kubernetes_secret_v1" "huggingface_token" {
  metadata {
    name      = "hf-token"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    token = var.huggingface_token
  }
}

resource "kubernetes_config_map_v1" "notebook" {
  metadata {
    name      = "notebook"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    "dogbooth.ipynb"           = file("${path.module}/src/notebook/dogbooth.ipynb")
    "llm_train_serve.ipynb"    = file("${path.module}/src/notebook/llm_train_serve.ipynb")
    "bert-training-yelp.ipynb" = file("${path.module}/src/notebook/bert-training-yelp.ipynb")
  }
}

#---------------------------------------------------------------
# Ray train cluster
#---------------------------------------------------------------
module "eks_blueprints_helm_install" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  helm_releases = {
    ray-cluster-train = {
      description      = "A Helm chart for RAY operator"
      namespace        = "ray-cluster-train"
      create_namespace = true
      chart            = "ray-cluster"
      chart_version    = "1.1.0"
      repository       = "https://ray-project.github.io/kuberay-helm/"
      values           = [file("${path.module}/helm-values/ray-train-cluster.yaml")]
    }
  }

  depends_on = [module.data_addons]
}

module "jupyterhub_single_user_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "jupyterhub-single-user"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess" # Define just the right permission for Jupyter Notebooks
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace_v1.jupyterhub.metadata[0].name}:jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "jupyterhub-single-user"
    namespace   = kubernetes_namespace_v1.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}
