# Troubleshooting Guide

## Common Issues and Solutions

### Issue 1: DaemonSet Pods Not Starting

**Symptoms:**
```bash
$ kubectl get pods -n monitoring -l app=dns-throttle-monitor
NAME                        READY   STATUS             RESTARTS
dns-throttle-monitor-abc    0/1     CrashLoopBackOff   5
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n monitoring dns-throttle-monitor-abc

# Check pod events
kubectl describe pod -n monitoring dns-throttle-monitor-abc
```

**Common Causes:**

1. **Missing AWS/Azure credentials**
```bash
   # For AWS - check IAM role attachment
   kubectl describe pod dns-throttle-monitor-abc -n monitoring | grep "AWS"
   
   # For Azure - check resource ID
   kubectl get daemonset dns-throttle-monitor -n monitoring -o yaml | grep AZURE_RESOURCE_ID
```
   
   **Solution:**
```bash
   # AWS: Attach IAM policy to node role
   aws iam attach-role-policy \
     --role-name <node-role> \
     --policy-arn arn:aws:iam::123456789:policy/DNS-Monitor-Policy
   
   # Azure: Set resource ID
   kubectl set env daemonset/dns-throttle-monitor \
     -n monitoring \
     AZURE_RESOURCE_ID="/subscriptions/SUB/resourceGroups/RG/providers/Microsoft.Compute/virtualMachineScaleSets/VMSS"
```

2. **Node exporter download failure**
   
   **Solution:**
```bash
   # Pre-download to a local registry
   docker pull prom/node-exporter:v1.7.0
   docker tag prom/node-exporter:v1.7.0 your-registry/node-exporter:v1.7.0
   docker push your-registry/node-exporter:v1.7.0
   
   # Update DaemonSet to use your registry
```

---

### Issue 2: No Metrics in Prometheus

**Symptoms:**
Query: kubernetes_dns_linklocal_allowance_exceeded
Result: No datapoints
**Diagnosis:**
```bash
# Check if ServiceMonitor is created
kubectl get servicemonitor -n monitoring dns-throttle-monitor

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
```

**Common Causes:**

1. **ServiceMonitor not discovered by Prometheus**
   
   **Check:**
```bash
   kubectl get servicemonitor -n monitoring dns-throttle-monitor -o yaml
```
   
   **Solution:**
   Ensure labels match Prometheus selector:
```yaml
   metadata:
     labels:
       release: prometheus  # Must match Prometheus installation
```

2. **Metrics not being exported**
   
   **Check:**
```bash
   # Port-forward to DaemonSet pod
   kubectl port-forward -n monitoring dns-throttle-monitor-abc 9100:9100
   
   # Check metrics endpoint
   curl http://localhost:9100/metrics | grep kubernetes_dns
```
   
   **Solution:**
```bash
   # Check if script is running
   kubectl exec -n monitoring dns-throttle-monitor-abc -- ps aux | grep monitor.sh
   
   # Manually run script
   kubectl exec -n monitoring dns-throttle-monitor-abc -- /scripts/monitor.sh
```

---

### Issue 3: Alerts Not Firing

**Symptoms:**
- Metrics show throttling
- No alerts in Alertmanager
- No notifications received

**Diagnosis:**
```bash
# Check if PrometheusRule exists
kubectl get prometheusrule -n monitoring dns-throttling-alerts

# Check Prometheus rules
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Navigate to Status → Rules
```

**Common Causes:**

1. **PrometheusRule not loaded**
   
   **Check:**
```bash
   kubectl get prometheusrule -n monitoring dns-throttling-alerts -o yaml
```
   
   **Solution:**
   Ensure correct labels:
```yaml
   metadata:
     labels:
       prometheus: kube-prometheus
       role: alert-rules
```

2. **Alert expression syntax error**
   
   **Solution:**
   Test query in Prometheus UI:
```promql
   kubernetes_dns_linklocal_allowance_exceeded > 0
```

3. **Alertmanager configuration issue**
   
   **Check:**
```bash
   # View Alertmanager config
   kubectl get secret -n monitoring \
     alertmanager-prometheus-kube-prometheus-alertmanager \
     -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

---

### Issue 4: Auto-Remediation Not Working

**Symptoms:**
- Alerts fire correctly
- CoreDNS does not scale
- No errors in webhook logs

**Diagnosis:**
```bash
# Check webhook logs
kubectl logs -n monitoring -l app=remediation-webhook --tail=50

# Check webhook health
kubectl port-forward -n monitoring svc/remediation-webhook 8080:8080
curl http://localhost:8080/health
```

**Common Causes:**

1. **Webhook not receiving alerts**
   
   **Test manually:**
```bash
   kubectl run test-curl --image=curlimages/curl --rm -it -- \
     curl -X POST http://remediation-webhook.monitoring.svc:8080/remediate \
     -H "Content-Type: application/json" \
     -d '{"alerts":[{"labels":{"alertname":"DNSThrottlingCritical"},"status":"firing"}]}'
```

2. **RBAC permissions missing**
   
   **Check:**
```bash
   kubectl auth can-i update deployments/scale \
     --as=system:serviceaccount:monitoring:dns-monitor \
     -n kube-system
```
   
   **Solution:**
```bash
   kubectl apply -f manifests/02-monitoring/clusterrole-dns-monitor.yaml
   kubectl apply -f manifests/02-monitoring/clusterrolebinding-dns-monitor.yaml
```

3. **Alertmanager not configured to call webhook**
   
   **Solution:**
   Update Alertmanager config:
```yaml
   receivers:
   - name: 'default'
     webhook_configs:
     - url: 'http://remediation-webhook.monitoring.svc.cluster.local:8080/remediate'
       send_resolved: true
```

---

### Issue 5: High CPU/Memory Usage

**Symptoms:**
```bash
$ kubectl top pods -n monitoring
NAME                           CPU    MEMORY
dns-throttle-monitor-abc       450m   512Mi  # Too high!
```

**Diagnosis:**
```bash
# Check resource requests/limits
kubectl describe pod -n monitoring dns-throttle-monitor-abc | grep -A 5 "Limits\|Requests"

# Check for metric explosion
kubectl exec -n monitoring dns-throttle-monitor-abc -- \
  wc -l /var/lib/node_exporter/textfile_collector/dns_throttle.prom
```

**Solution:**

1. **Increase resource limits:**
```yaml
   resources:
     requests:
       cpu: 200m
       memory: 256Mi
     limits:
       cpu: 500m
       memory: 512Mi
```

2. **Reduce scrape frequency:**
   Edit monitoring script to collect every 120 seconds instead of 60.

---

### Issue 6: NodeLocal DNS Cache Conflicts

**Symptoms:**
- DNS resolution slow after deploying NodeLocal DNS
- Some pods can't resolve DNS

**Diagnosis:**
```bash
# Check if NodeLocal DNS is running
kubectl get daemonset -n kube-system node-local-dns

# Check pod DNS configuration
kubectl get pod <pod-name> -o yaml | grep -A 10 dnsConfig
```

**Solution:**

Some clusters need manual pod DNS configuration:
```yaml
spec:
  dnsConfig:
    nameservers:
    - 169.254.20.10  # NodeLocal DNS
  dnsPolicy: "None"
```

---

## Debugging Commands Cheat Sheet
```bash
# Check all monitoring components
kubectl get all -n monitoring

# View DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=100 -f

# Check metrics endpoint
kubectl port-forward -n monitoring ds/dns-throttle-monitor 9100:9100
curl localhost:9100/metrics | grep kubernetes_dns

# Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Browse to http://localhost:9090/targets

# Alert status
# Browse to http://localhost:9090/alerts

# Grafana dashboards
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Browse to http://localhost:3000

# Test webhook
kubectl run test --image=curlimages/curl --rm -it -- \
  curl -X POST http://remediation-webhook.monitoring.svc:8080/health

# Check CoreDNS status
kubectl get deployment coredns -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

---

## Getting Help

If you're still stuck:

1. **Collect diagnostic information:**
```bash
   # Run this script to collect all relevant info
   ./scripts/collect-diagnostics.sh > diagnostics.txt
```

2. **Open an issue:**
   - Go to https://github.com/bharathcs/kubernetes-dns-autoheal/issues
   - Include diagnostics output
   - Describe what you've tried

3. **Community support:**
   - Join our Discussions: https://github.com/bharathcs/kubernetes-dns-autoheal/discussions
   - Slack channel: Coming soon

---

## Known Limitations

1. **CloudWatch API rate limits:**
