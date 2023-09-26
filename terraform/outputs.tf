output "bucket_name" {
  value       = aws_s3_bucket.fm_ops_data.id
  description = "Bucket used for host Datasets for training and Ray model checkpoints during training"
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}
