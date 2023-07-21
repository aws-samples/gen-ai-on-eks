output "private_subnets" {
  value = module.vpc.private_subnets
}

output "karpenter_data" {
  value = module.eks_blueprints_addons.karpenter
}