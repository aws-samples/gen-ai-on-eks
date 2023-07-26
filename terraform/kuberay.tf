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