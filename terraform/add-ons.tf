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

# module "karpenter" {
#   source  = "terraform-aws-modules/eks/aws//modules/karpenter"
#   version = "~> 19.15"

#   cluster_name                 = module.eks.cluster_name
#   irsa_oidc_provider_arn       = module.eks.oidc_provider_arn
#   create_irsa                  = false # IRSA will be created by the kubernetes-addons module
#   iam_role_additional_policies = [module.karpenter_policy.arn]

#   tags = local.tags
# }

resource "aws_iam_role_policy_attachment" "karpenter_attach_policy_to_role" {
  role       = element(split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn), 1)
  policy_arn = module.karpenter_policy.arn
}

# # EFS CSI Missing Policy
# resource "aws_iam_policy" "aws_efs_csi_driver_tags" {
#   name        = "${module.eks.cluster_name}-efs-csi-tag-policy"
#   description = "IAM Policy for AWS EFS CSI Driver Tags"
#   policy      = data.aws_iam_policy_document.aws_efs_csi_driver_tags.json
#   tags        = local.tags
# }

# data "aws_iam_policy_document" "aws_efs_csi_driver_tags" {
#   statement {
#     sid    = "AllowTagResource"
#     effect = "Allow"
#     resources = [
#       aws_efs_file_system.efs.arn, aws_efs_file_system.efs_dags_airflow.arn
#     ]
#     actions = ["elasticfilesystem:TagResource"]

#     condition {
#       test     = "StringLike"
#       variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
#       values   = ["true"]
#     }
#   }
# }


# Update to latest version of Blueprints
module "eks_blueprints_addons" {
  # source  = "aws-ia/eks-blueprints-addons/aws"
  # version = "~> 1.0" #ensure to update this to the latest/desired version
  source            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=v1.2.2"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_efs_csi_driver = true # Will be used for Jupyter Notebooks and DAG on Apache Airflow
  # aws_efs_csi_driver_irsa_policies    = [resource.aws_iam_policy.aws_efs_csi_driver_tags.arn]
  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  karpenter_enable_spot_termination = true
  enable_metrics_server             = true
  enable_kube_prometheus_stack      = true

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

resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
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

#---------------------------------------------------------------
# Self-Managed Apache Airflow
#---------------------------------------------------------------

# TBD: Need to create Karpenter provisioner for AirFlow

resource "random_password" "postgres" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "postgres" {
  name                    = "postgres-2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = aws_secretsmanager_secret.postgres.id
  secret_string = random_password.postgres.result
}


module "security_group_rds_airflow" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-rds-airflow"
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = "${module.vpc.vpc_cidr_block}"
    },
  ]

  tags = local.tags
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = var.airflow_name

  engine               = "postgres"
  engine_version       = "14.3"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.m6i.xlarge"

  storage_type      = "io1"
  allocated_storage = 100
  iops              = 3000

  db_name                = var.airflow_name
  username               = var.airflow_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres.secret_string)
  port                   = 5432

  multi_az             = true
  db_subnet_group_name = module.vpc.database_subnet_group

  vpc_security_group_ids = [module.security_group_rds_airflow.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 5
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "airflow-metastore"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Airflow Postgres Metastore for monitoring role"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
}

# Namespace to install Airflow Helm Release
resource "kubernetes_namespace_v1" "airflow" {
  metadata {
    name = "apache-airflow"
  }
  timeouts {
    delete = "15m"
  }
}

# Bucket for Airflow logs
module "airflow_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${var.name}-logs-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Policy to assign to Airflow Scheduler IRSA
data "aws_iam_policy_document" "airflow_s3_logs" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket.s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket.s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }
}

resource "aws_iam_policy" "airflow_scheduler" {
  description = "IAM policy for Airflow Scheduler Pod"
  name_prefix = "airflow-scheduler"
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs.json
}

# IRSA for AirFlow Scheduler
module "airflow_irsa_scheduler" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "airflow-scheduler"

  role_policy_arns = merge({ AirflowScheduler = aws_iam_policy.airflow_scheduler.arn })


  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace_v1.airflow.metadata[0].name}:airflow-scheduler"]
    }
  }
}

resource "kubernetes_service_account_v1" "airflow_scheduler" {
  metadata {
    name        = "airflow-scheduler"
    namespace   = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_scheduler.iam_role_arn }
  }

  automount_service_account_token = true
}

# TBD: Need to understand what this secret is used for
resource "kubernetes_secret_v1" "airflow_scheduler" {
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_scheduler.metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_scheduler.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# IRSA to Airflow webserver
resource "kubernetes_service_account_v1" "airflow_webserver" {
  metadata {
    name        = "airflow-webserver"
    namespace   = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_webserver.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_webserver" {
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_webserver.metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_webserver.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_webserver" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "airflow-webserver"

  role_policy_arns = merge({ AirflowWebserver = aws_iam_policy.airflow_webserver.arn })

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace_v1.airflow.metadata[0].name}:airflow-webserver"]
    }
  }
}

resource "aws_iam_policy" "airflow_webserver" {
  description = "IAM policy for Airflow Webserver Pod"
  name_prefix = "airflow-webserver"
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs.json
}

resource "random_id" "airflow_webserver" {
  byte_length = 16
}

resource "aws_secretsmanager_secret" "airflow_webserver" {
  name                    = "airflow_webserver_secret_key_2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "airflow_webserver" {
  secret_id     = aws_secretsmanager_secret.airflow_webserver.id
  secret_string = random_id.airflow_webserver.hex
}

# WebServer Secret Key
resource "kubectl_manifest" "airflow_webserver" {
  sensitive_fields = [
    "data.webserver-secret-key"
  ]

  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
   name: airflow-webserver-secret-key
   namespace: ${kubernetes_namespace_v1.airflow.metadata[0].name}
   labels:
    app.kubernetes.io/managed-by: "Helm"
   annotations:
    meta.helm.sh/release-name: "airflow"
    meta.helm.sh/release-namespace: "airflow"
type: Opaque
data:
  webserver-secret-key: ${base64encode(aws_secretsmanager_secret_version.airflow_webserver.secret_string)}
YAML
}

# Airflow Worker Needed Permissions
resource "kubernetes_service_account_v1" "airflow_worker" {
  metadata {
    name        = "airflow-worker"
    namespace   = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_worker.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_worker" {
  metadata {
    name      = "airflow-worker-secret"
    namespace = kubernetes_namespace_v1.airflow.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_worker.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_worker" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "airflow-worker"

  role_policy_arns = merge({ AirflowWorker = aws_iam_policy.airflow_worker.arn })

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace_v1.airflow.metadata[0].name}:airflow-worker"]
    }
  }
}

resource "aws_iam_policy" "airflow_worker" {
  description = "IAM policy for Airflow Workers Pod"
  name_prefix = "airflow-worker"
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs.json
}

#---------------------------------------------------------------
# Managing DAG files with GitSync - EFS Storage Class
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs_dags_airflow" {
  creation_token = "efs-airflow"
  encrypted      = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt_airflow" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.efs_dags_airflow.id
  subnet_id       = element(module.vpc.private_subnets, count.index)
  security_groups = [aws_security_group.efs_airflow.id]
}

resource "aws_security_group" "efs_airflow" {
  name        = "${local.name}-efs-airflow"
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

# EFS Storage Class for AirFlow
resource "kubectl_manifest" "efs_sc" {
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.efs_dags_airflow.id}
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
YAML

  depends_on = [module.eks.cluster_name]
}

resource "kubectl_manifest" "efs_pvc" {
  yaml_body = <<-YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: airflowdags-pvc
  namespace: ${kubernetes_namespace_v1.airflow.metadata[0].name}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 10Gi
YAML

  depends_on = [kubectl_manifest.efs_sc]
}

resource "helm_release" "apache_airflow" {
  namespace        = kubernetes_namespace_v1.airflow.metadata[0].name
  create_namespace = false
  name             = "airflow"
  repository       = "https://airflow.apache.org"
  chart            = "airflow"
  version          = "1.9.0"
  wait             = false # This parameter is used for complete DB migrations to DB
  # values = ["${file("${var.kuberay_cluster_values_path}")}"]
  values = [templatefile(var.apache_airflow_values_path, {
    airflow_version       = "2.6.3"
    airflow_db_user       = var.airflow_name
    airflow_db_pass       = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
    airflow_db_host       = try(element(split(":", module.db.db_instance_endpoint), 0), "")
    airflow_db_name       = try(module.db.db_instance_name, "")
    webserver_secret_name = "airflow-webserver-secret-key"

    airflow_workers_service_account_name   = kubernetes_service_account_v1.airflow_worker.metadata[0].name
    airflow_scheduler_service_account_name = kubernetes_service_account_v1.airflow_scheduler.metadata[0].name
    webserver_service_account_name         = kubernetes_service_account_v1.airflow_webserver.metadata[0].name
    s3_bucket_name                         = try(module.airflow_s3_bucket.s3_bucket_id, "")
    efs_pvc                                = "airflowdags-pvc"
  })]

  depends_on = [
    module.eks, module.db, kubernetes_namespace_v1.airflow, module.airflow_s3_bucket,
    aws_iam_policy.airflow_scheduler, aws_iam_policy.airflow_webserver, aws_iam_policy.airflow_worker,
    kubectl_manifest.airflow_webserver, module.airflow_irsa_scheduler, module.airflow_irsa_webserver,
    module.airflow_irsa_worker, aws_efs_file_system.efs_dags_airflow, aws_efs_mount_target.efs_mt_airflow
  ]
}


