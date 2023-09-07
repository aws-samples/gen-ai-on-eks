#---------------------------------------------------------------
# Self-Managed Apache Airflow
#---------------------------------------------------------------
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
  engine_version       = "14.7"
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