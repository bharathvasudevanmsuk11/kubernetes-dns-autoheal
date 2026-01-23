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
cd kubernetes-dns-autoheal

# Make scripts executable
chmod +x scripts/*.sh

# Run installer
./scripts/install.sh

# Select option 1 for AWS EKS
```

## Step 5: Verify Installation
```bash
# Run validation
./scripts/validate.sh

# Check DaemonSet pods (one per node)
kubectl get pods -n monitoring -l app=dns-throttle-monitor

# Check logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=20

# Should see: "Collecting AWS metrics..."
```

## Step 6: Verify Metrics Collection
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Open browser: http://localhost:9090
# Query: kubernetes_dns_linklocal_allowance_exceeded
# Should show data from your nodes
```

## Step 7: Configure Alerting

Edit the Alertmanager configuration:
```bash
nano manifests/06-alerting/secret-alertmanager-config.yaml

# Update:
# - Slack webhook URL
# - Email addresses
# - PagerDuty key

# Apply changes
kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml

# Restart Alertmanager
kubectl rollout restart statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

## Step 8: Access Dashboards

### Grafana
```bash
# Get password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open: http://localhost:3000
# Login: admin / <password>
```

### Prometheus
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open: http://localhost:9090
```

## Troubleshooting

### Issue: No metrics in Prometheus

**Check IAM permissions:**
```bash
# Verify policy is attached
aws iam list-attached-role-policies --role-name $NODE_ROLE

# Check DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=50
```

### Issue: "Access Denied" in logs

**Solution:**
```bash
# Ensure IAM policy is correct
aws iam get-policy-version \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy \
  --version-id v1

# Re-attach if needed
aws iam detach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy

aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy
```

## Cost Considerations

### CloudWatch API Costs

- ~100 GetMetricStatistics calls per node per hour
- Cost: ~$0.01 per 1,000 calls
- **Total: ~$0.01/day per cluster**

### EC2 Instance Recommendations

For DNS-intensive workloads:

| Workload Size | Recommended Instance | DNS Capacity |
|---------------|---------------------|--------------|
| Small | m5.large | ~2,000 DNS queries/sec |
| Medium | m5.xlarge | ~4,000 DNS queries/sec |
| Large | m5.2xlarge | ~8,000 DNS queries/sec |

## Cleanup

To remove the solution:
```bash
./scripts/cleanup.sh

# Optionally remove IAM policy
aws iam detach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy

aws iam delete-policy \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy
```

## Next Steps

1. Run load test: `./tests/load-test/run-load-test.sh`
2. Configure Slack/PagerDuty alerts
3. Review dashboards weekly
4. Monitor for capacity trends

## Support

- Issues: https://github.com/bharathvasudevanmsuk11/kubernetes-dns-autoheal/issues
- Docs: https://github.com/bharathcsvasudevanmsuk11/kubernetes-dns-autoheal/blob/main/docs/
