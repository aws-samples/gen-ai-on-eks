output "bucket_name" {
  value       = aws_s3_bucket.fm_ops_data.id
  description = "Bucket used for host Datasets for training and Ray model checkpoints during training"
}