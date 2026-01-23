# Implementation Guide

## Complete Step-by-Step Implementation of Kubernetes DNS Auto-Heal

This guide walks you through implementing the complete DNS throttling prevention solution from scratch. Follow these steps exactly for a successful deployment.

---

## Table of Contents

1. [Pre-Implementation Checklist](#pre-implementation-checklist)
2. [Phase 1: Environment Preparation](#phase-1-environment-preparation)
3. [Phase 2: Deploy Monitoring Infrastructure](#phase-2-deploy-monitoring-infrastructure)
4. [Phase 3: Configure Observability](#phase-3-configure-observability)
5. [Phase 4: Implement Auto-Scaling](#phase-4-implement-auto-scaling)
6. [Phase 5: Setup Auto-Remediation](#phase-5-setup-auto-remediation)
7. [Phase 6: Configure Alerting](#phase-6-configure-alerting)
8. [Phase 7: Production Deployment](#phase-7-production-deployment)
9. [Phase 8: Validation and Testing](#phase-8-validation-and-testing)
10. [Post-Implementation](#post-implementation)

---

## Pre-Implementation Checklist

### Required Access

- [ ] kubectl access to target cluster with admin privileges
- [ ] Ability to create namespaces, DaemonSets, and RBAC resources
- [ ] Cloud provider console access (AWS/Azure)
- [ ] Helm 3.0+ installed locally
- [ ] git installed locally

### Required Information

**For AWS EKS:**
- [ ] AWS Account ID
- [ ] EKS Cluster name
- [ ] Node IAM role name
- [ ] AWS region

**For Azure AKS:**
- [ ] Azure Subscription ID
- [ ] Resource Group name
- [ ] AKS Cluster name
- [ ] VMSS (Virtual Machine Scale Set) name

### Communication Channels

- [ ] Slack webhook URL (for notifications)
- [ ] PagerDuty integration key (for critical alerts)
- [ ] Email addresses for SRE team and management
- [ ] SMTP server details (if using email alerts)

### Time Requirements

- **Development/Staging:** 2-3 hours
- **Production:** 4-6 hours (including validation)
- **Best Practice:** Deploy to staging first, validate for 1 week, then production

---

## Phase 1: Environment Preparation

### Step 1.1: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/bharathcs/kubernetes-dns-autoheal.git
cd kubernetes-dns-autoheal

# Verify all files are present
ls -la manifests/
ls -la scripts/

# Make scripts executable
chmod +x scripts/*.sh
```

### Step 1.2: Configure Cloud Provider Credentials

#### For AWS EKS:

**Create IAM Policy:**

```bash
# Create policy file
cat > dns-monitor-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create the policy
aws iam create-policy \
  --policy-name DNS-Throttling-Monitor-Policy \
  --policy-document file://dns-monitor-policy.json \
  --description "Policy for DNS throttling monitoring"

# Note the Policy ARN from the output
# Example: arn:aws:iam::123456789012:policy/DNS-Throttling-Monitor-Policy
```

**Attach Policy to Node Role:**

```bash
# Get your node role name
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`)].RoleName' \
  --output text)

echo "Node Role: $NODE_ROLE"

# Attach the policy
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/DNS-Throttling-Monitor-Policy

# Verify attachment
aws iam list-attached-role-policies --role-name $NODE_ROLE
```

#### For Azure AKS:

**Get Resource Information:**

```bash
# Get VMSS Resource ID
RESOURCE_ID=$(az vmss list \
  --resource-group YOUR_RESOURCE_GROUP \
  --query "[?contains(name, 'aks')].id" \
  --output tsv)

echo "Resource ID: $RESOURCE_ID"

# Save this for later use
echo $RESOURCE_ID > azure-resource-id.txt
```

**Assign Monitoring Permissions:**

```bash
# Get the AKS managed identity
IDENTITY=$(az aks show \
  --resource-group YOUR_RESOURCE_GROUP \
  --name YOUR_CLUSTER_NAME \
  --query identityProfile.kubeletidentity.clientId \
  --output tsv)

# Assign Monitoring Reader role
az role assignment create \
  --assignee $IDENTITY \
  --role "Monitoring Reader" \
  --scope $RESOURCE_ID

# Verify role assignment
az role assignment list \
  --assignee $IDENTITY \
  --scope $RESOURCE_ID
```

### Step 1.3: Verify Cluster Access

```bash
# Verify kubectl is configured
kubectl cluster-info

# Check current context
kubectl config current-context

# Verify you have admin access
kubectl auth can-i create namespace
kubectl auth can-i create clusterrole
kubectl auth can-i create daemonset

# All should return "yes"
```

### Step 1.4: Create Backup

```bash
# Backup existing CoreDNS configuration
kubectl get deployment coredns -n kube-system -o yaml > coredns-backup.yaml

# Backup existing Prometheus (if exists)
helm list -n monitoring > helm-backup.txt

# Save current cluster state
kubectl get all -A > cluster-state-backup.txt
```

---

## Phase 2: Deploy Monitoring Infrastructure

### Step 2.1: Create Monitoring Namespace

```bash
# Create namespace
kubectl apply -f manifests/01-namespace/monitoring-namespace.yaml

# Verify
kubectl get namespace monitoring
```

### Step 2.2: Deploy Prometheus and Grafana

```bash
# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  --wait --timeout=10m

# Verify installation
kubectl get pods -n monitoring

# Expected output:
# NAME                                                   READY   STATUS
# prometheus-kube-prometheus-operator-xxx                1/1     Running
# prometheus-prometheus-kube-prometheus-prometheus-0     2/2     Running
# prometheus-grafana-xxx                                 3/3     Running
# alertmanager-prometheus-kube-prometheus-alertmanager-0 2/2     Running
```

**Wait for all pods to be Running** before proceeding (usually 2-3 minutes).

### Step 2.3: Deploy DNS Monitoring DaemonSet

```bash
# Deploy RBAC resources
kubectl apply -f manifests/02-monitoring/serviceaccount-dns-monitor.yaml
kubectl apply -f manifests/02-monitoring/clusterrole-dns-monitor.yaml
kubectl apply -f manifests/02-monitoring/clusterrolebinding-dns-monitor.yaml

# Deploy monitoring script ConfigMap
kubectl apply -f manifests/02-monitoring/configmap-monitoring-script.yaml

# Deploy DaemonSet
kubectl apply -f manifests/02-monitoring/daemonset-dns-monitor.yaml

# Verify DaemonSet
kubectl get daemonset -n monitoring dns-throttle-monitor

# Expected: One pod per node
# NAME                    DESIRED   CURRENT   READY
# dns-throttle-monitor    3         3         3

# Check pod status
kubectl get pods -n monitoring -l app=dns-throttle-monitor
```

**For Azure AKS - Configure Resource ID:**

```bash
# Set the Azure resource ID from Step 1.2
kubectl set env daemonset/dns-throttle-monitor \
  -n monitoring \
  AZURE_RESOURCE_ID="$(cat azure-resource-id.txt)"

# Verify
kubectl get daemonset dns-throttle-monitor -n monitoring -o yaml | grep AZURE_RESOURCE_ID
```

### Step 2.4: Verify Metrics Collection

```bash
# Wait 2 minutes for first metrics collection

# Check DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=20

# Expected output should include:
# "Collecting AWS metrics..." (or Azure)
# "AWS metrics collected successfully" (or Azure)

# Port-forward to check metrics endpoint
kubectl port-forward -n monitoring daemonset/dns-throttle-monitor 9100:9100 &

# Check metrics
curl http://localhost:9100/metrics | grep kubernetes_dns

# You should see metrics like:
# kubernetes_dns_linklocal_allowance_exceeded{instance="i-xxx",platform="aws"} 0

# Kill port-forward
killall kubectl
```

---

## Phase 3: Configure Observability

### Step 3.1: Deploy ServiceMonitor

```bash
# Deploy Service for DaemonSet
kubectl apply -f manifests/03-prometheus-grafana/service-dns-monitor.yaml

# Deploy ServiceMonitor for Prometheus discovery
kubectl apply -f manifests/03-prometheus-grafana/servicemonitor-dns-metrics.yaml

# Verify ServiceMonitor
kubectl get servicemonitor -n monitoring dns-throttle-monitor

# Check if Prometheus discovered the target
# Wait 30 seconds, then:
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Open browser: http://localhost:9090/targets
# Look for "dns-throttle-monitor" target - should be UP
```

### Step 3.2: Configure Prometheus Rules

```bash
# Deploy PrometheusRule for alerts
kubectl apply -f manifests/03-prometheus-grafana/prometheusrule-dns-alerts.yaml

# Verify rules are loaded
kubectl get prometheusrule -n monitoring dns-throttling-alerts

# Check in Prometheus UI
# Browse to: http://localhost:9090/rules
# You should see: dns_throttling group with multiple alerts
```

### Step 3.3: Import Grafana Dashboard

```bash
# Get Grafana admin password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
echo

# Port-forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Open browser: http://localhost:3000
# Login: admin / <password from above>

# Import dashboard:
# 1. Click "+" → Import
# 2. Upload: grafana/dashboards/dns-throttling-overview.json
# 3. Select Prometheus datasource
# 4. Click Import
```

**Alternatively, deploy as ConfigMap:**

```bash
kubectl apply -f manifests/03-prometheus-grafana/grafana-dashboard-configmap.yaml

# Restart Grafana to pick up dashboard
kubectl rollout restart deployment prometheus-grafana -n monitoring
```

---

## Phase 4: Implement Auto-Scaling

### Step 4.1: Deploy CoreDNS Auto-Scaler

```bash
# Deploy RBAC for autoscaler
kubectl apply -f manifests/04-autoscaling/serviceaccount-dns-autoscaler.yaml
kubectl apply -f manifests/04-autoscaling/clusterrole-dns-autoscaler.yaml
kubectl apply -f manifests/04-autoscaling/clusterrolebinding-dns-autoscaler.yaml

# Deploy autoscaler configuration
kubectl apply -f manifests/04-autoscaling/configmap-dns-autoscaler.yaml

# Deploy autoscaler
kubectl apply -f manifests/04-autoscaling/deployment-dns-autoscaler.yaml

# Verify autoscaler is running
kubectl get deployment -n kube-system dns-autoscaler

# Check logs
kubectl logs -n kube-system -l app=dns-autoscaler --tail=20

# Expected output:
# "Scaling target deployment/coredns in namespace kube-system"
# Current replicas and target replicas logged
```

### Step 4.2: Test Auto-Scaling

```bash
# Check current CoreDNS replicas
kubectl get deployment coredns -n kube-system

# Note the current replica count

# The autoscaler will adjust based on:
# replicas = ceil(nodes/16) + ceil(cores/256)
# min: 2, max: 10

# For a 3-node cluster with 12 total cores:
# replicas = ceil(3/16) + ceil(12/256) = 1 + 1 = 2 (but min is 2)

# Watch for changes over next 5 minutes
watch kubectl get deployment coredns -n kube-system
```

### Step 4.3: Deploy NodeLocal DNS Cache

```bash
# Deploy NodeLocal DNS Cache
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

# Verify DaemonSet
kubectl get daemonset -n kube-system node-local-dns

# Expected: One pod per node
kubectl get pods -n kube-system -l k8s-app=node-local-dns

# Test DNS resolution through NodeLocal DNS
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

**Important:** NodeLocal DNS cache can reduce DNS load by 80%!

---

## Phase 5: Setup Auto-Remediation

### Step 5.1: Deploy Remediation Webhook

```bash
# Deploy webhook ConfigMap (contains Python code)
kubectl apply -f manifests/05-remediation/configmap-remediation-webhook.yaml

# Deploy webhook Deployment
kubectl apply -f manifests/05-remediation/deployment-remediation-webhook.yaml

# Deploy webhook Service
kubectl apply -f manifests/05-remediation/service-remediation-webhook.yaml

# Verify webhook is running
kubectl get deployment -n monitoring remediation-webhook
kubectl get pods -n monitoring -l app=remediation-webhook

# Check logs
kubectl logs -n monitoring -l app=remediation-webhook --tail=20

# Expected output:
# "Starting remediation webhook on port 8080"
```

### Step 5.2: Test Webhook Manually

```bash
# Test health endpoint
kubectl run test-webhook --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://remediation-webhook.monitoring.svc:8080/health

# Expected: {"status": "healthy"}

# Test remediation endpoint
kubectl run test-webhook --image=curlimages/curl --rm -it --restart=Never -- \
  curl -X POST http://remediation-webhook.monitoring.svc:8080/remediate \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {"alertname": "DNSThrottlingWarning"},
      "annotations": {"summary": "Test alert"}
    }]
  }'

# Expected: {"status": "remediated", "action": "scaled_coredns"}

# Verify CoreDNS was scaled
kubectl get deployment coredns -n kube-system
# Should show 4 replicas (from test alert)
```

---

## Phase 6: Configure Alerting

### Step 6.1: Configure Slack Integration

**Get Slack Webhook URL:**

1. Go to https://api.slack.com/messaging/webhooks
2. Create a new webhook for your workspace
3. Select channel: `#sre-alerts`
4. Copy the webhook URL

**Update Alertmanager Configuration:**

```bash
# Edit the secret
kubectl edit secret -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager

# Find the slack_api_url line and update:
# slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

# Save and exit

# Or apply from manifest after editing:
# Edit manifests/06-alerting/secret-alertmanager-config.yaml
# Replace YOUR/SLACK/WEBHOOK with your actual webhook path

kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml
```

### Step 6.2: Configure Email Notifications

**Update Alertmanager Secret:**

```bash
# Edit manifests/06-alerting/secret-alertmanager-config.yaml

# Update these fields:
# - to: 'your-sre-team@company.com'
# - from: 'alertmanager@company.com'
# - smarthost: 'smtp.gmail.com:587'
# - auth_username: 'alerts@company.com'
# - auth_password: 'YOUR_APP_PASSWORD'

# For Gmail, create an App Password:
# https://support.google.com/accounts/answer/185833

kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml
```

### Step 6.3: Configure PagerDuty

**Get PagerDuty Integration Key:**

1. Log into PagerDuty
2. Go to Services → Your Service → Integrations
3. Add Integration → Prometheus
4. Copy the Integration Key

**Update Alertmanager:**

```bash
# Edit manifests/06-alerting/secret-alertmanager-config.yaml
# Replace YOUR_PAGERDUTY_KEY with actual key

kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml
```

### Step 6.4: Restart Alertmanager

```bash
# Restart to pick up new configuration
kubectl rollout restart statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring

# Wait for ready
kubectl rollout status statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring

# Verify configuration loaded
kubectl logs -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0 -c alertmanager | grep -i "loaded"
```

### Step 6.5: Test Alert Routing

```bash
# Use the test script
./scripts/test-alerts.sh

# This will send a test alert to Alertmanager
# Check:
# 1. Slack channel for notification
# 2. Email inbox
# 3. Remediation webhook logs:
kubectl logs -n monitoring -l app=remediation-webhook --tail=50
```

---

## Phase 7: Production Deployment

### Step 7.1: Final Verification Checklist

Run the validation script:

```bash
./scripts/validate.sh
```

**Expected output:**
```
=========================================
DNS Throttling Solution - Validation
=========================================

Checking Monitoring namespace... ✅ PASS
Checking DNS Monitor DaemonSet... ✅ PASS
Checking DNS Monitor pods running... ✅ PASS
Checking Prometheus installed... ✅ PASS
Checking Prometheus pod running... ✅ PASS
Checking ServiceMonitor created... ✅ PASS
Checking PrometheusRule created... ✅ PASS
Checking CoreDNS autoscaler... ✅ PASS
Checking Remediation webhook... ✅ PASS
Checking Remediation webhook pods... ✅ PASS
✅ Metrics are being collected

=========================================
✅ All checks passed!
=========================================
```

### Step 7.2: Production Cutover

**For Staging → Production:**

```bash
# Switch context to production
kubectl config use-context production-cluster

# Run full installation
./scripts/install.sh

# Select appropriate platform (AWS/Azure)
# Enter configuration details when prompted

# Validate production deployment
./scripts/validate.sh
```

### Step 7.3: Monitor Closely (First 24 Hours)

```bash
# Keep Grafana dashboard open
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Watch DaemonSet pods
watch kubectl get pods -n monitoring -l app=dns-throttle-monitor

# Monitor CoreDNS behavior
watch kubectl get deployment coredns -n kube-system

# Check for any alerts
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Browse to: http://localhost:9090/alerts
```

---

## Phase 8: Validation and Testing

### Step 8.1: Run Load Test

```bash
cd tests/load-test

# Deploy DNS load test
./run-load-test.sh

# This creates 10 pods making continuous DNS queries

# Monitor in Grafana:
# - DNS query rate should increase
# - If throttling occurs, alerts should fire
# - CoreDNS should auto-scale

# Watch CoreDNS scaling
watch kubectl get deployment coredns -n kube-system

# Check metrics in Prometheus
# Query: kubernetes_dns_linklocal_allowance_exceeded
# Should see increase if load is high enough
```

### Step 8.2: Verify Auto-Remediation Flow

```bash
# Trigger a test alert manually (simulates throttling)
kubectl run trigger-alert --image=curlimages/curl --rm -it -- \
  curl -X POST http://remediation-webhook.monitoring.svc:8080/remediate \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {"alertname": "DNSThrottlingCritical"},
      "annotations": {"summary": "Critical DNS throttling"}
    }]
  }'

# Expected flow:
# 1. Webhook receives alert
# 2. Webhook scales CoreDNS to 6 replicas
# 3. Slack notification sent
# 4. Check each step:

# Step 1: Check webhook logs
kubectl logs -n monitoring -l app=remediation-webhook --tail=20

# Step 2: Verify CoreDNS scaled
kubectl get deployment coredns -n kube-system
# Should show 6 replicas

# Step 3: Check Slack channel
# Should see notification
```

### Step 8.3: Cleanup Load Test

```bash
# Remove load test deployment
kubectl delete deployment dns-load-test

# Verify cleanup
kubectl get deployments | grep dns-load-test
# Should return nothing
```

---

## Post-Implementation

### Step 9.1: Documentation

**Create Runbook for Your Team:**

```bash
# Copy and customize runbooks
cp runbooks/dns-throttling-warning.md runbooks/YOUR_COMPANY-dns-warning.md
cp runbooks/dns-throttling-critical.md runbooks/YOUR_COMPANY-dns-critical.md

# Update with:
# - Your company-specific escalation paths
# - Your Slack channels
# - Your PagerDuty rotation
# - Your incident management process
```

### Step 9.2: Team Training

**Share with team:**

1. **Grafana Dashboard:** http://your-grafana-url
2. **Prometheus Alerts:** http://your-prometheus-url/alerts
3. **Runbooks:** Link to your internal wiki
4. **Escalation Path:** When to page, when to escalate

**Host a demo session:**
- Show the Grafana dashboard
- Explain each metric
- Walk through a simulated incident
- Practice using runbooks

### Step 9.3: Set Up Ongoing Monitoring

**Weekly Review:**
```bash
# Export last week's metrics
# Add to your weekly SRE review
```

**Monthly Capacity Planning:**
```bash
# Review CoreDNS scaling trends
# Check if max replicas need adjustment
# Review node capacity vs DNS load
```

### Step 9.4: Continuous Improvement

**Monitor These KPIs:**

| Metric | Target | Review Frequency |
|--------|--------|------------------|
| DNS-related incidents | 0 | Weekly |
| Mean time to detection | <60 seconds | Weekly |
| Mean time to resolution | <5 minutes | Weekly |
| False positive rate | <5% | Monthly |
| Auto-remediation success rate | >95% | Monthly |

**Tune as needed:**
- Adjust alert thresholds if too many false positives
- Increase max CoreDNS replicas if frequently hitting limit
- Review and update runbooks based on actual incidents

---

## Rollback Procedure

If you need to rollback:

```bash
# Use the cleanup script
./scripts/cleanup.sh

# Restore CoreDNS backup
kubectl apply -f coredns-backup.yaml

# Remove Prometheus (if desired)
helm uninstall prometheus -n monitoring

# Delete namespace
kubectl delete namespace monitoring
```

---

## Success Criteria

✅ All validation checks pass
✅ Metrics visible in Prometheus and Grafana
✅ Alerts configured and tested
✅ Auto-remediation tested and working
✅ Team trained on dashboards and runbooks
✅ No DNS-related incidents in first week
✅ Auto-scaling responding appropriately to load

---

## Getting Help

If you encounter issues during implementation:

1. **Check logs:**
   ```bash
   kubectl logs -n monitoring -l app=dns-throttle-monitor
   kubectl logs -n monitoring -l app=remediation-webhook
   ```

2. **Review troubleshooting guide:**
   - See [Troubleshooting Guide](troubleshooting.md)

3. **Open an issue:**
   - https://github.com/bharathvasudevanmsuk11/kubernetes-dns-autoheal/issues

4. **Contact:**
   - Email: bharathcs@example.com
   - LinkedIn: [Bharath Vasudevan](https://www.linkedin.com/in/bharath-vasudevan-b4b07315/)

---

## Next Steps

After successful implementation:

- [ ] Document your specific configuration
- [ ] Add to your disaster recovery plan
- [ ] Schedule quarterly review of thresholds
- [ ] Consider contributing improvements back to the project
- [ ] Share your success story!

---

**Congratulations!** You've successfully implemented zero-touch DNS throttling prevention! 🎉
