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

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.15"

  cluster_name                 = module.eks.cluster_name
  irsa_oidc_provider_arn       = module.eks.oidc_provider_arn
  create_irsa                  = false # IRSA will be created by the kubernetes-addons module
  iam_role_additional_policies = [module.karpenter_policy.arn]

  tags = local.tags
}

# Update to latest version of Blueprints
module "eks_blueprints_addons" {
  # source  = "aws-ia/eks-blueprints-addons/aws"
  # version = "~> 1.0" #ensure to update this to the latest/desired version
  source            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650fd2b4bc894bde7b51313a8dc9598d82e925"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_efs_csi_driver           = true # Will be used for Jupyter Notebooks and DAG on Apache Airflow
  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true
  karpenter_helm_config = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  karpenter_node_iam_instance_profile        = module.karpenter.instance_profile_name
  karpenter_enable_spot_termination_handling = true
  enable_metrics_server                      = true
  enable_kube_prometheus_stack               = true

  tags = {
    Environment = "mlops-dev"
  }
}

#---------------------------------------------------------------
# Jupyterhub Stack
#---------------------------------------------------------------

resource "kubectl_manifest" "karpenter_for_jupyter" {
  yaml_body = file("${var.jupyter_karpenter_config}")

  depends_on = [
    module.eks, module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "karpenter_for_jupyter_node_template" {
  yaml_body = file("${var.jupyter_karpenter_config_node_template}")

  depends_on = [
    module.eks, module.eks_blueprints_addons
  ]
}

resource "helm_release" "jupyterhub" {
  namespace        = "jupyterhub"
  create_namespace = true
  name             = "jupyterhub"
  repository       = "https://jupyterhub.github.io/helm-chart/"
  chart            = "jupyterhub"
  version          = "2.0.0"

  values = ["${file("${var.jupyter_hub_values_path}")}"]

  depends_on = [
    module.eks, module.eks_blueprints_addons, kubectl_manifest.karpenter_for_jupyter,
    aws_efs_file_system.efs, aws_efs_mount_target.efs_mt
  ]
}

resource "kubectl_manifest" "storage_class_gp3" {
  yaml_body = <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  csi.storage.k8s.io/fstype: ext4
  encrypted: "true"
YAML

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# EFS Filesystem for private volumes per user
# This will be repalced with Dynamic EFS provision using EFS CSI Driver
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs"
  encrypted      = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = element(module.vpc.private_subnets, count.index)
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}

resource "kubectl_manifest" "pv" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist
  namespace: jupyterhub
spec:
  capacity:
    storage: 123Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: ${aws_efs_file_system.efs.dns_name}
    path: "/"
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pvc" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-persist
  namespace: jupyterhub
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Gi
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pv_shared" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist-shared
  namespace: jupyterhub
spec:
  capacity:
    storage: 123Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: ${aws_efs_file_system.efs.dns_name}
    path: "/"
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pvc_shared" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-persist-shared
  namespace: jupyterhub
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Gi
YAML

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# KubeRay Operator
#---------------------------------------------------------------
resource "helm_release" "rayoperator" {
  namespace        = "kuberay-operator" # Might change the name of this namespace
  create_namespace = true
  name             = "kuberay-operator"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = "0.5.0"

  # values = ["${file("${var.kuberay_values_path}")}"]

  depends_on = [
    module.eks
  ]
}

#---------------------------------------------------------------
# KubeRay Cluster
#---------------------------------------------------------------
resource "kubectl_manifest" "karpenter_for_ray_cluster" {
  yaml_body = file("${var.raycluster_karpenter_config}")

  depends_on = [
    module.eks, module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "karpenter_for_ray_cluster_node_template" {
  yaml_body = file("${var.raycluster_karpenter_config_node_template}")

  depends_on = [
    module.eks, module.eks_blueprints_addons
  ]
}

resource "helm_release" "ray_cluster" {
  namespace        = "kuberay-operator"
  create_namespace = true
  name             = "ray-cluster"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "ray-cluster"
  version          = "0.5.0"

  values = ["${file("${var.kuberay_cluster_values_path}")}"]

  depends_on = [
    module.eks, kubectl_manifest.karpenter_for_ray_cluster, kubectl_manifest.karpenter_for_ray_cluster_node_template
  ]
}