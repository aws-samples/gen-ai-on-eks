locals {
  name       = var.name
  region     = coalesce(var.aws_region, data.aws_region.current.name)
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  private_subnets    = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  public_subnets     = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 5, k + 8)]
  secondary_ip_range = [for k, v in local.azs : cidrsubnet(element(var.secondary_cidr_blocks, 0), 1, k)]

  tags = {
    Sample     = var.name
    GithubRepo = "github.com/aws-samples/gen-ai-on-eks"
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_partition" "current" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks
  private_subnets       = concat(local.private_subnets, local.secondary_ip_range)
  public_subnets        = local.public_subnets
  enable_nat_gateway    = true
  single_nat_gateway    = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}


################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.12"

  cluster_name                   = local.name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id = module.vpc.vpc_id
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
  substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 0
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    # Allows Control Plane Nodes to talk to Worker nodes on all ports.
    # Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on
    # e.g., coreDNS 53, metrics-server 4443.
    # Update this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    ebs_optimized = true
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 100
          volume_type = "gp3"
        }
      }
    }
  }


  # Baseline nodes to run add-ons
  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting system add-ons"
      # Filtering only Secondary CIDR private subnets starting with "100.".
      # Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2/recommended/image_id --region us-west-2
      ami_type     = "AL2_x86_64" # Use this for Graviton AL2_ARM_64
      min_size     = 2
      max_size     = 8
      desired_size = 2

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name = "core-node-grp"
      })
    }
    gpu1 = {
      name        = "gpu-node-grp"
      description = "EKS Node Group to run GPU workloads"
      # Filtering only Secondary CIDR private subnets starting with "100.".
      # Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      ami_type     = "AL2_x86_64_GPU"
      min_size     = 1
      max_size     = 1
      desired_size = 1

      instance_types = ["g5.12xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "gpu"
      }

      taints = {
        gpu = {
          key      = "nvidia.com/gpu"
          effect   = "NO_SCHEDULE"
          operator = "EXISTS"
        }
      }

      tags = merge(local.tags, {
        Name = "gpu-node-grp"
      })
    }
  }

  node_security_group_tags = {
    "kubernetes.io/cluster/${local.name}" = null # Tag needed otherwise will have multiple sgs with same tag
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}
