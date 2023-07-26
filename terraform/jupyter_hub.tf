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

resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "jupyterhub-single-user"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess" # Define just the right permission for Jupyter Notebooks
  }


  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub.metadata[0].name}:jupyterhub-single-user"]
    }
  }
}

# Airflow Worker Needed Permissions
resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  metadata {
    name      = "jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

resource "helm_release" "jupyterhub" {
  namespace        = "jupyterhub"
  create_namespace = false
  name             = "jupyterhub"
  repository       = "https://jupyterhub.github.io/helm-chart/"
  chart            = "jupyterhub"
  version          = "2.0.0"

  values = ["${file("${var.jupyter_hub_values_path}")}"]

  depends_on = [
    module.eks, module.eks_blueprints_addons, kubectl_manifest.karpenter_for_jupyter,
    aws_efs_file_system.efs, aws_efs_mount_target.efs_mt, kubernetes_namespace.jupyterhub
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

# EFS for script persistance from JupyterHub
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

  depends_on = [module.eks_blueprints_addons, kubernetes_namespace.jupyterhub]
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

  depends_on = [module.eks_blueprints_addons, kubernetes_namespace.jupyterhub]
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

  depends_on = [module.eks_blueprints_addons, kubernetes_namespace.jupyterhub]
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

  depends_on = [module.eks_blueprints_addons, kubernetes_namespace.jupyterhub]
}