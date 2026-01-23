# Quick Start Guide

> **Essential checklist and commands for deploying Kubernetes DNS Auto-Heal**

---

## ⚡ TL;DR - 5 Minute Deploy

```bash
git clone https://github.com/bharathcs/kubernetes-dns-autoheal.git
cd kubernetes-dns-autoheal
chmod +x scripts/*.sh
./scripts/install.sh
./scripts/validate.sh
```

---

## ✅ Complete Manifest Files Checklist

Before deploying, ensure all these files exist in your `manifests/` directory:

### 📂 01-namespace/ (1 file)
- [x] `monitoring-namespace.yaml`

### 📂 02-monitoring/ (5 files)
- [x] `serviceaccount-dns-monitor.yaml`
- [x] `clusterrole-dns-monitor.yaml`
- [x] `clusterrolebinding-dns-monitor.yaml`
- [x] `configmap-monitoring-script.yaml`
- [x] `daemonset-dns-monitor.yaml`

### 📂 03-prometheus-grafana/ (4 files)
- [x] `service-dns-monitor.yaml`
- [x] `servicemonitor-dns-metrics.yaml`
- [x] `prometheusrule-dns-alerts.yaml`
- [x] `grafana-dashboard-configmap.yaml`

### 📂 04-autoscaling/ (5 files)
- [x] `serviceaccount-dns-autoscaler.yaml`
- [x] `clusterrole-dns-autoscaler.yaml`
- [x] `clusterrolebinding-dns-autoscaler.yaml`
- [x] `configmap-dns-autoscaler.yaml`
- [x] `deployment-dns-autoscaler.yaml`

### 📂 05-remediation/ (3 files)
- [x] `configmap-remediation-webhook.yaml`
- [x] `deployment-remediation-webhook.yaml`
- [x] `service-remediation-webhook.yaml`

### 📂 06-alerting/ (1 file)
- [x] `secret-alertmanager-config.yaml`

**Total: 19 manifest files**

### Verify All Files Exist

```bash
# Quick check
ls -R manifests/

# Count files
find manifests/ -name "*.yaml" | wc -l
# Should output: 19
```

---

## 🔧 Before Deploying - Configuration Checklist

### ⚠️ CRITICAL: Update These Values

#### 1. For Azure AKS Users

**File:** `manifests/02-monitoring/daemonset-dns-monitor.yaml`

```yaml
env:
- name: AZURE_RESOURCE_ID
  value: "/subscriptions/YOUR_SUB_ID/resourceGroups/YOUR_RG/providers/Microsoft.Compute/virtualMachineScaleSets/YOUR_VMSS"
```

**How to get this:**
```bash
az vmss list --resource-group YOUR_RG --query "[0].id" -o tsv
```

#### 2. For AWS EKS Users

**File:** `manifests/02-monitoring/daemonset-dns-monitor.yaml`

```yaml
env:
- name: AWS_DEFAULT_REGION
  value: "us-east-1"  # Change to your region
```

Also ensure IAM policy is attached to node role (see [Implementation Guide](docs/implementation-guide.md#step-12-configure-cloud-provider-credentials))

#### 3. Configure Slack Notifications

**File:** `manifests/06-alerting/secret-alertmanager-config.yaml`

```yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
```

**Get webhook:** https://api.slack.com/messaging/webhooks

Update channel name:
```yaml
- name: 'sre-slack'
  slack_configs:
  - channel: '#sre-alerts'  # Change to your channel
```

#### 4. Configure Email Alerts

**File:** `manifests/06-alerting/secret-alertmanager-config.yaml`

```yaml
- name: 'sre-email'
  email_configs:
  - to: 'sre-team@company.com'           # Change this
    from: 'alertmanager@company.com'      # Change this
    smarthost: 'smtp.gmail.com:587'       # Change if not Gmail
    auth_username: 'alerts@company.com'   # Change this
    auth_password: 'YOUR_APP_PASSWORD'    # Change this
```

**For Gmail:** Create App Password at https://support.google.com/accounts/answer/185833

#### 5. Configure PagerDuty (Optional)

**File:** `manifests/06-alerting/secret-alertmanager-config.yaml`

```yaml
- name: 'pagerduty-critical'
  pagerduty_configs:
  - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'  # Change this
```

---

## 📋 Pre-Deployment Validation

### Check Prerequisites

```bash
# Kubernetes version (1.21+)
kubectl version --short

# Helm version (3.0+)
helm version --short

# Cluster access
kubectl cluster-info

# Admin permissions
kubectl auth can-i create namespace
kubectl auth can-i create clusterrole
kubectl auth can-i create daemonset
# All should return "yes"
```

### Validate YAML Syntax

```bash
# Dry-run all manifests
kubectl apply --dry-run=client -f manifests/01-namespace/
kubectl apply --dry-run=client -f manifests/02-monitoring/
kubectl apply --dry-run=client -f manifests/03-prometheus-grafana/
kubectl apply --dry-run=client -f manifests/04-autoscaling/
kubectl apply --dry-run=client -f manifests/05-remediation/
kubectl apply --dry-run=client -f manifests/06-alerting/

# If no errors, you're good to go!
```

---

## 🚀 Deployment Commands

### Option 1: Automated Installation (Recommended)

```bash
# One-command install
./scripts/install.sh

# Follow prompts to select platform (AWS/Azure)
# Script will:
# - Install Prometheus/Grafana
# - Deploy all monitoring components
# - Configure auto-scaling
# - Deploy remediation webhook
```

### Option 2: Manual Step-by-Step

```bash
# Step 1: Install Prometheus Stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Step 2: Deploy Monitoring
kubectl apply -f manifests/01-namespace/
kubectl apply -f manifests/02-monitoring/

# For Azure - Set Resource ID
kubectl set env daemonset/dns-throttle-monitor \
  -n monitoring \
  AZURE_RESOURCE_ID="YOUR_RESOURCE_ID"

# Step 3: Deploy Observability
kubectl apply -f manifests/03-prometheus-grafana/

# Step 4: Deploy Auto-Scaling
kubectl apply -f manifests/04-autoscaling/

# Step 5: Deploy Remediation
kubectl apply -f manifests/05-remediation/

# Step 6: Configure Alerting
kubectl apply -f manifests/06-alerting/

# Restart Alertmanager
kubectl rollout restart statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring

# Step 7: Deploy NodeLocal DNS Cache
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```

---

## ✅ Post-Deployment Validation

### Run Validation Script

```bash
./scripts/validate.sh
```

**Expected Output:**
```
=========================================
DNS Throttling Solution - Validation
=========================================

Checking Monitoring namespace... ✅ PASS
Checking DNS Monitor DaemonSet... ✅ PASS
Checking DNS Monitor pods running... ✅ PASS
Checking Prometheus installed... ✅ PASS
Checking ServiceMonitor created... ✅ PASS
Checking PrometheusRule created... ✅ PASS
Checking CoreDNS autoscaler... ✅ PASS
Checking Remediation webhook... ✅ PASS
✅ Metrics are being collected

=========================================
✅ All checks passed!
=========================================
```

### Manual Verification

```bash
# 1. Check all pods are running
kubectl get pods -n monitoring

# 2. Check DaemonSet coverage
kubectl get daemonset -n monitoring dns-throttle-monitor
# DESIRED should equal number of nodes

# 3. Check metrics endpoint
kubectl port-forward -n monitoring daemonset/dns-throttle-monitor 9100:9100 &
curl localhost:9100/metrics | grep kubernetes_dns
killall kubectl

# 4. Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
# Browse to http://localhost:9090/targets
# Look for "dns-throttle-monitor" - should be UP

# 5. Check Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
# Browse to http://localhost:3000
# Login: admin / (get password below)
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

---

## 🧪 Testing

### Test Alert Flow

```bash
# Send test alert
./scripts/test-alerts.sh

# Check:
# 1. Slack channel for notification
# 2. Email inbox
# 3. Webhook logs
kubectl logs -n monitoring -l app=remediation-webhook --tail=50
```

### Run Load Test

```bash
cd tests/load-test
./run-load-test.sh

# This creates 10 pods making continuous DNS queries
# Monitor in Grafana to see metrics increase
# CoreDNS should auto-scale if load is high

# Cleanup
kubectl delete deployment dns-load-test
```

---

## 🔍 Accessing Dashboards

### Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Get password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Open: http://localhost:3000
# Login: admin / <password>
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open: http://localhost:9090
```

### Alertmanager

```bash
kubectl port-forward -n monitoring svc/alertmanager-prometheus-kube-prometheus-alertmanager 9093:9093

# Open: http://localhost:9093
```

---

## 🔧 Common Configuration Changes

### Adjust Alert Thresholds

**File:** `manifests/03-prometheus-grafana/prometheusrule-dns-alerts.yaml`

```yaml
- alert: DNSThrottlingWarning
  expr: kubernetes_dns_linklocal_allowance_exceeded > 10  # Change threshold
  for: 2m  # Change duration
```

Apply changes:
```bash
kubectl apply -f manifests/03-prometheus-grafana/prometheusrule-dns-alerts.yaml
```

### Increase CoreDNS Max Replicas

**File:** `manifests/04-autoscaling/configmap-dns-autoscaler.yaml`

```json
{
  "max": 20  // Increase from 10
}
```

Apply changes:
```bash
kubectl apply -f manifests/04-autoscaling/configmap-dns-autoscaler.yaml
kubectl rollout restart deployment dns-autoscaler -n kube-system
```

### Update Slack Channel

**File:** `manifests/06-alerting/secret-alertmanager-config.yaml`

```yaml
- channel: '#new-channel-name'
```

Apply changes:
```bash
kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml
kubectl rollout restart statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

---

## 🆘 Quick Troubleshooting

### No Metrics in Prometheus

```bash
# Check DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=50

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring dns-throttle-monitor

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Browse to http://localhost:9090/targets
```

### Alerts Not Firing

```bash
# Check PrometheusRule
kubectl get prometheusrule -n monitoring dns-throttling-alerts

# Check in Prometheus UI
# Browse to http://localhost:9090/rules
```

### Auto-Remediation Not Working

```bash
# Check webhook logs
kubectl logs -n monitoring -l app=remediation-webhook --tail=50

# Test webhook manually
kubectl run test --image=curlimages/curl --rm -it -- \
  curl -X POST http://remediation-webhook.monitoring.svc:8080/health
```

**See full troubleshooting guide:** [docs/troubleshooting.md](docs/troubleshooting.md)

---

## 🗑️ Uninstall

```bash
# Use cleanup script
./scripts/cleanup.sh

# Or manual cleanup
kubectl delete -f manifests/06-alerting/
kubectl delete -f manifests/05-remediation/
kubectl delete -f manifests/04-autoscaling/
kubectl delete -f manifests/03-prometheus-grafana/
kubectl delete -f manifests/02-monitoring/
kubectl delete -f manifests/01-namespace/

# Optionally remove Prometheus
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

---

## 📚 Additional Resources

- **Full Implementation Guide:** [docs/implementation-guide.md](docs/implementation-guide.md)
- **Architecture Details:** [docs/architecture.md](docs/architecture.md)
- **Troubleshooting:** [docs/troubleshooting.md](docs/troubleshooting.md)
- **FAQ:** [docs/faq.md](docs/faq.md)

---

## 💡 Pro Tips

1. **Always deploy to staging first** - Validate for 1 week before production
2. **Monitor the monitors** - Check DaemonSet health regularly
3. **Tune alert thresholds** - Adjust based on your cluster's baseline
4. **Review dashboards weekly** - Look for capacity trends
5. **Keep runbooks updated** - Add notes from real incidents

---

## 🎯 Success Metrics

After deployment, you should see:

- ✅ Zero DNS-related incidents
- ✅ <60 second detection time
- ✅ <5 minute auto-remediation
- ✅ <5% false positive rate
- ✅ >95% auto-remediation success rate

---

## 🆘 Getting Help

- **Issues:** https://github.com/bharathvasudevanmsuk11/kubernetes-dns-autoheal/issues
- **Discussions:** https://github.com/bharathvasudevanmsuk11/kubernetes-dns-autoheal/discussions
- **Email:** Coming Soon
- **LinkedIn:** [Bharath Vasudevan](https://www.linkedin.com/in/bharath-vasudevan-b4b07315/)

---

**Last Updated:** January 2026  
**Version:** 1.0.0
