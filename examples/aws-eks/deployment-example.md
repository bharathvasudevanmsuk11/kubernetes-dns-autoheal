# AWS EKS Deployment Guide

Complete step-by-step guide for deploying the DNS Auto-Heal solution on AWS EKS.

## Prerequisites

- AWS CLI configured
- eksctl installed
- kubectl installed
- AWS account with appropriate permissions

## Step 1: Create EKS Cluster (Optional)

If you don't have an existing cluster:
```bash
# Create cluster using example config
eksctl create cluster -f cluster-config.yaml

# This takes ~15-20 minutes
```

Or use an existing cluster:
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name YOUR_CLUSTER_NAME
```

## Step 2: Create IAM Policy
```bash
# Create the policy
aws iam create-policy \
  --policy-name DNS-Throttling-Monitor-Policy \
  --policy-document file://iam-policy.json \
  --description "Policy for DNS throttling monitoring on EKS"

# Note the Policy ARN from output
# Example: arn:aws:iam::123456789012:policy/DNS-Throttling-Monitor-Policy
```

## Step 3: Attach Policy to Node Role

### Method 1: Find and Attach to Existing Role
```bash
# Get the node instance role name
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`) || contains(RoleName, `eksctl`)].RoleName' \
  --output text | head -1)

echo "Node Role: $NODE_ROLE"

# Attach the policy
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy

# Verify attachment
aws iam list-attached-role-policies --role-name $NODE_ROLE
```

### Method 2: Use eksctl (if cluster was created with eksctl)
```bash
# Get cluster name
CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 | cut -d'.' -f1)

# Attach policy to node group
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=monitoring \
  --name=dns-monitor \
  --attach-policy-arn=arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy \
  --approve
```

## Step 4: Deploy DNS Auto-Heal Solution
```bash
# Clone repository
git clone https://github.com/bharathcs/kubernetes-dns-autoheal.git
cd kubernetes-dns-aut
