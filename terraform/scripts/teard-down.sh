#!/bin/bash

echo "Scaling in deployments"

for NS in $(kubectl get ns | egrep -v 'kube-|amazon|default|karpenter')
  do kubectl get deploy -n $NS --no-headers -o name | xargs kubectl -n $NS scale --replicas 0
  done

echo "Removing LoadBalancers"

kubectl -n apache-airflow delete ingress apache-airflow-airflow-ingress

echo "Terminating remaning instances"

aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --filters "Name=tag:"aws:eks:cluster-name",Values=fmops-cluster" | awk -F '"' '/i-/{print $2}' | xargs aws ec2 terminate-instances --instance-ids 

echo "Cleaning up Buckets"
export BUCKET_NAME=$(terraform output -raw bucket_name)
aws s3 rm s3://$BUCKET_NAME --recursive

echo "Running Terraform Destroy"

terraform destroy -auto-approve