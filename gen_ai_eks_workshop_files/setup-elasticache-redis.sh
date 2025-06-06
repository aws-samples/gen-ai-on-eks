#!/bin/bash

# Complete ElastiCache Serverless Redis Setup Script
# This script creates an ElastiCache Serverless Redis cluster for an existing EKS cluster
# and configures all necessary security group rules

set -e  # Exit on any error

# Configuration
EKS_CLUSTER_NAME="genai-workshop"
REDIS_CACHE_NAME="genai-eks-redis-cache"
SECURITY_GROUP_NAME="genai-redis-serverless-sg"
SUBNET_GROUP_NAME="genai-redis-subnet-group"

echo "🚀 Starting ElastiCache Serverless Redis setup for EKS cluster: $EKS_CLUSTER_NAME"

# Check if EKS cluster exists
echo "📋 Checking if EKS cluster exists..."
if ! aws eks describe-cluster --name $EKS_CLUSTER_NAME &>/dev/null; then
    echo "❌ Error: EKS cluster '$EKS_CLUSTER_NAME' not found!"
    echo "Please create the EKS cluster first before running this script."
    exit 1
fi
echo "✅ EKS cluster found"

# Get VPC ID from EKS cluster
echo "🔍 Getting VPC ID from EKS cluster..."
VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo "❌ Error: Could not retrieve VPC ID from EKS cluster"
    exit 1
fi
echo "✅ VPC ID: $VPC_ID"

# Get subnet IDs from EKS cluster
echo "🔍 Getting subnet IDs from EKS cluster..."
ALL_SUBNET_IDS=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
if [ -z "$ALL_SUBNET_IDS" ] || [ "$ALL_SUBNET_IDS" == "None" ]; then
    echo "❌ Error: Could not retrieve subnet IDs from EKS cluster"
    exit 1
fi

# Take only the first 3 subnet IDs
SUBNET_IDS=$(echo $ALL_SUBNET_IDS | tr ' ' '\n' | head -3 | tr '\n' ' ')
echo "✅ All Subnet IDs: $ALL_SUBNET_IDS"
echo "✅ Using first 3 Subnet IDs: $SUBNET_IDS"

# Get EKS cluster security group ID
echo "🔍 Getting EKS cluster security group ID..."
EKS_SG_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
if [ -z "$EKS_SG_ID" ] || [ "$EKS_SG_ID" == "None" ]; then
    echo "❌ Error: Could not retrieve EKS cluster security group ID"
    exit 1
fi
echo "✅ EKS Security Group ID: $EKS_SG_ID"

# Get EKS node security groups
echo "🔍 Getting EKS node security groups..."
NODE_SG_IDS=$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$EKS_CLUSTER_NAME" --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text | sort | uniq)
if [ -z "$NODE_SG_IDS" ]; then
    echo "⚠️ Warning: Could not find security groups for EKS nodes. Using cluster security group only."
    NODE_SG_IDS=$EKS_SG_ID
else
    echo "✅ Found EKS node security groups: $NODE_SG_IDS"
fi

# Check if security group already exists
echo "🔍 Checking if Redis security group already exists..."
EXISTING_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
    echo "✅ Using existing security group: $EXISTING_SG"
    REDIS_SG_ID=$EXISTING_SG
else
    # Create security group for Redis
    echo "🔐 Creating security group for Redis..."
    REDIS_SG_ID=$(aws ec2 create-security-group \
        --group-name $SECURITY_GROUP_NAME \
        --description "Security group for Redis Serverless cluster" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    echo "✅ Created security group: $REDIS_SG_ID"

    # Allow Redis traffic from EKS cluster
    echo "🔐 Adding ingress rule for Redis traffic from EKS cluster..."
    aws ec2 authorize-security-group-ingress \
        --group-id $REDIS_SG_ID \
        --protocol tcp \
        --port 6379 \
        --source-group $EKS_SG_ID
    echo "✅ Ingress rule added for EKS cluster security group"
fi

# Add ingress rules for each node security group
for NODE_SG_ID in $NODE_SG_IDS; do
    if [ "$NODE_SG_ID" != "$EKS_SG_ID" ]; then  # Skip if it's the same as cluster SG
        echo "🔐 Adding ingress rule for Redis traffic from node group $NODE_SG_ID..."
        
        # Check if rule already exists
        EXISTING_RULE=$(aws ec2 describe-security-groups --group-ids $REDIS_SG_ID --query "SecurityGroups[0].IpPermissions[?FromPort==\`6379\` && ToPort==\`6379\` && contains(UserIdGroupPairs[*].GroupId, \`$NODE_SG_ID\`)]" --output text)
        
        if [ -n "$EXISTING_RULE" ]; then
            echo "✅ Rule already exists for $NODE_SG_ID"
        else
            aws ec2 authorize-security-group-ingress \
                --group-id $REDIS_SG_ID \
                --protocol tcp \
                --port 6379 \
                --source-group $NODE_SG_ID
            echo "✅ Ingress rule added for $NODE_SG_ID"
        fi
    fi
done

# Check if ElastiCache Serverless already exists
echo "🔍 Checking if Redis cache already exists..."
EXISTING_CACHE=$(aws elasticache describe-serverless-caches --serverless-cache-name $REDIS_CACHE_NAME --query 'ServerlessCaches[0].Status' --output text 2>/dev/null || echo "None")

if [ "$EXISTING_CACHE" != "None" ] && [ -n "$EXISTING_CACHE" ]; then
    echo "⚠️  Redis cache '$REDIS_CACHE_NAME' already exists with status: $EXISTING_CACHE"
    if [ "$EXISTING_CACHE" == "available" ]; then
        echo "✅ Cache is available, skipping creation"
    else
        echo "⏳ Cache is in '$EXISTING_CACHE' state, waiting for it to become available..."
    fi
else
    # Create ElastiCache Serverless Redis
    echo "📦 Creating ElastiCache Serverless Redis cluster..."
    aws elasticache create-serverless-cache \
        --serverless-cache-name $REDIS_CACHE_NAME \
        --engine redis \
        --subnet-ids $SUBNET_IDS \
        --security-group-ids $REDIS_SG_ID
    echo "✅ ElastiCache Serverless Redis creation initiated"
fi

# Wait for Redis cache to be available
echo "⏳ Waiting for Redis cache to be available (this may take 2-3 minutes)..."
WAIT_COUNT=0
MAX_WAIT=60  # 30 minutes max wait (60 * 30 seconds)

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    CACHE_STATUS=$(aws elasticache describe-serverless-caches \
        --serverless-cache-name $REDIS_CACHE_NAME \
        --query 'ServerlessCaches[0].Status' \
        --output text 2>/dev/null || echo "creating")
    
    if [ "$CACHE_STATUS" == "available" ]; then
        echo "✅ Redis cache is now available!"
        break
    elif [ "$CACHE_STATUS" == "failed" ]; then
        echo "❌ Redis cache creation failed!"
        exit 1
    else
        echo "🔄 Cache status: $CACHE_STATUS (waited $((WAIT_COUNT * 30)) seconds)"
        sleep 30
        WAIT_COUNT=$((WAIT_COUNT + 1))
    fi
done

if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
    echo "❌ Timeout waiting for Redis cache to become available"
    exit 1
fi

# Get Redis endpoint
echo "🔍 Getting Redis endpoint..."
REDIS_ENDPOINT=$(aws elasticache describe-serverless-caches \
    --serverless-cache-name $REDIS_CACHE_NAME \
    --query 'ServerlessCaches[0].Endpoint.Address' \
    --output text)

if [ -z "$REDIS_ENDPOINT" ] || [ "$REDIS_ENDPOINT" == "None" ]; then
    echo "❌ Error: Could not retrieve Redis endpoint"
    exit 1
fi

# Test Redis connection
echo "🔍 Testing Redis connection..."
echo "Creating a temporary pod to test Redis connection..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: redis-test
  labels:
    app: redis-test
spec:
  containers:
  - name: redis-cli
    image: redis:latest
    command:
    - "/bin/bash"
    - "-c"
    - |
      apt-get update && apt-get install -y ca-certificates
      echo "Testing connection to Redis with TLS..."
      redis-cli -h $REDIS_ENDPOINT --tls -p 6379 ping
      echo "Connection test completed."
      sleep 30
EOF

echo "⏳ Waiting for test pod to complete..."
sleep 20

# Check test pod logs
TEST_RESULT=$(kubectl logs redis-test | grep -A 1 "Testing connection" || echo "Test failed")
echo "📋 Test result: $TEST_RESULT"

# Clean up test pod
kubectl delete pod redis-test --grace-period=0 --force

# Display summary
echo ""
echo "🎉 ElastiCache Serverless Redis setup completed successfully!"
echo "================================================="
echo "EKS Cluster Name: $EKS_CLUSTER_NAME"
echo "Redis Cache Name: $REDIS_CACHE_NAME"
echo ""
echo "🔗 REDIS CONNECTION DETAILS:"
echo "   Hostname/Endpoint: $REDIS_ENDPOINT"
echo "   Port: 6379"
echo "   Full Connection String: $REDIS_ENDPOINT:6379"
echo ""
echo "📝 To connect from your EKS pods, use:"
echo "   Host: $REDIS_ENDPOINT"
echo "   Port: 6379"
echo "   SSL/TLS: Enabled"
echo "================================================="
echo "✅ Script completed successfully!"
