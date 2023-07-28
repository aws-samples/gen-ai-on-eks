#---------------------------------------------------------------
# Karpenter Permissions
#---------------------------------------------------------------

# We have to augment default the karpenter node IAM policy with
# permissions we need for Ray Jobs to run until IRSA is added
# upstream in kuberay-operator. See issue
# https://github.com/ray-project/kuberay/issues/746
module "karpenter_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 5.20"

  name        = "KarpenterS3ReadOnlyPolicy"
  description = "IAM Policy to allow read from an S3 bucket for karpenter nodes"

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
          Action   = "s3:Get*"
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

module "eks_blueprints_addons" {
  source            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=v1.2.2"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_efs_csi_driver = true # Will be used for Jupyter Notebooks and DAG on Apache Airflow
  # aws_efs_csi_driver_irsa_policies    = [resource.aws_iam_policy.aws_efs_csi_driver_tags.arn]
  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true
  # karpenter = {
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  # }
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
      values           = ["${file("${var.nvidia_gpu_values_path}")}"]
    }
  }

  tags = {
    Environment = "mlops-dev"
  }
}

resource "kubectl_manifest" "karpenter_default" {
  yaml_body = file("${var.karpenter_default_provisioner}")

  depends_on = [
    module.eks, module.eks_blueprints_addons.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_default_node_template" {
  yaml_body = file("${var.karpenter_default_node_template}")

  depends_on = [
    module.eks, module.eks_blueprints_addons.karpenter
  ]
}


