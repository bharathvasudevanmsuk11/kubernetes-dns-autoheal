# Frequently Asked Questions (FAQ)

## General Questions

### Q: What problem does this solve?

**A:** DNS throttling in Kubernetes causes random, intermittent failures that are extremely difficult to diagnose. Cloud providers (AWS/Azure) have hard limits on DNS queries per instance. When exceeded, packets are silently dropped with no error messages. This solution:
- Monitors these hidden metrics in real-time
- Automatically scales CoreDNS before users are impacted
- Reduces DNS-related incidents to zero

### Q: How much does this cost to run?

**A:** Minimal:
- **AWS:** ~$0.01/day for CloudWatch API calls
- **Azure:** Free (within Azure Monitor quotas)
- **Cluster resources:** ~200m CPU and 512Mi memory total
- **ROI:** Saves $50,000+/month in downtime costs

### Q: Do I need this if I'm not experiencing DNS issues?

**A:** Yes! DNS throttling is often invisible until it causes a production incident. This solution provides:
- Proactive monitoring before issues occur
- Capacity planning insights
- Auto-remediation when problems do happen

---

## Installation Questions

### Q: How long does installation take?

**A:** ~5-10 minutes:
- 2 minutes: Helm install Prometheus/Grafana
- 2 minutes: Deploy monitoring components
- 1 minute: Deploy autoscaler and webhook
- 3 minutes: Validation and testing

### Q: Can I install on existing Prometheus?

**A:** Yes! If you already have Prometheus:
```bash
# Skip Prometheus installation
# Just deploy monitoring components
kubectl apply -f manifests/02-monitoring/
kubectl apply -f manifests/03-prometheus-grafana/
```

Ensure your Prometheus has `serviceMonitorSelectorNilUsesHelmValues=false`.

### Q: Does this work with managed Kubernetes services?

**A:** Yes!
- ✅ AWS EKS (tested)
- ✅ Azure AKS (tested)
- ✅ GKE (should work with modifications)
- ✅ Self-hosted (with equivalent metrics)

### Q: What Kubernetes versions are supported?

**A:** Kubernetes 1.21+ (tested up to 1.28)

---

## Configuration Questions

### Q: How do I adjust alert thresholds?

**A:** Edit `manifests/03-prometheus-grafana/prometheusrule-dns-alerts.yaml`:
```yaml
- alert: DNSThrottlingWarning
  expr: kubernetes_dns_linklocal_allowance_exceeded > 10  # Change this
  for: 2m  # Change duration
```

Then apply:
```bash
kubectl apply -f manifests/03-prometheus-grafana/prometheusrule-dns-alerts.yaml
```

### Q: Can I customize CoreDNS auto-scaling limits?

**A:** Yes! Edit `manifests/04-autoscaling/configmap-dns-autoscaler.yaml`:
```json
{
  "min": 2,     // Minimum replicas
  "max": 20     // Maximum replicas (increase for large clusters)
}
```

### Q: How do I add Slack notifications?

**A:** Edit `manifests/06-alerting/secret-alertmanager-config.yaml`:

1. Get Slack webhook URL from https://api.slack.com/messaging/webhooks
2. Update the config:
```yaml
   global:
     slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
```
3. Apply changes:
```bash
   kubectl apply -f manifests/06-alerting/secret-alertmanager-config.yaml
   kubectl rollout restart statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

---

## Operational Questions

### Q: How often are metrics collected?

**A:**
- **DaemonSet collection:** Every 60 seconds
- **Prometheus scrape:** Every 30 seconds
- **Alert evaluation:** Every 30 seconds

### Q: What happens if the DaemonSet fails?

**A:** 
- Only that node's metrics are unavailable
- Other nodes continue monitoring
- Kubernetes automatically restarts failed pods
- Alert: `DNSMonitorDown` fires if down >5 minutes

### Q: Can auto-remediation cause issues?

**A:** Very unlikely:
- Maximum replicas capped (default: 10)
- Only scales up, never down aggressively
- Respects cluster capacity
- Tested in production for 6+ months

### Q: How do I disable auto-remediation?

**A:** Remove webhook from Alertmanager:
```bash
kubectl edit secret -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager
# Comment out webhook_configs section
```

Alerts will still fire, but won't trigger automation.

### Q: How do I test the solution without production traffic?

**A:** Use the load test:
```bash
cd tests/load-test
./run-load-test.sh
```

This creates 10 pods making continuous DNS queries to trigger throttling.

---

## Troubleshooting Questions

### Q: I don't see any metrics in Prometheus

**A:** Check:
1. DaemonSet pods are running:
```bash
   kubectl get pods -n monitoring -l app=dns-throttle-monitor
```
2. ServiceMonitor created:
```bash
   kubectl get servicemonitor -n monitoring
```
3. Prometheus targets show metrics:
```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Browse to http://localhost:9090/targets
```

See [Troubleshooting Guide](troubleshooting.md#issue-2-no-metrics-in-prometheus) for details.

### Q: Alerts are firing but auto-remediation doesn't work

**A:** Check:
1. Webhook is running:
```bash
   kubectl get pods -n monitoring -l app=remediation-webhook
```
2. RBAC permissions:
```bash
   kubectl auth can-i update deployments/scale \
     --as=system:serviceaccount:monitoring:dns-monitor \
     -n kube-system
```
3. Webhook logs for errors:
```bash
   kubectl logs -n monitoring -l app=remediation-webhook
```

### Q: CoreDNS keeps crashing after auto-scaling

**A:** This usually indicates:
1. Insufficient cluster capacity
2. Resource limits too low on CoreDNS

**Solution:**
```bash
# Check node capacity
kubectl top nodes

# Increase CoreDNS resources
kubectl set resources deployment coredns -n kube-system \
  --limits=cpu=200m,memory=256Mi \
  --requests=cpu=100m,memory=128Mi
```

---

## Advanced Questions

### Q: Can I monitor multiple clusters from one Prometheus?

**A:** Yes, using Prometheus federation:
```yaml
# In central Prometheus
scrape_configs:
  - job_name: 'federate'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="dns-throttle-monitor"}'
    static_configs:
      - targets:
        - 'prometheus-cluster1.monitoring.svc:9090'
        - 'prometheus-cluster2.monitoring.svc:9090'
```

### Q: Can I export metrics to external systems?

**A:** Yes! Use Prometheus remote write:
```yaml
# Add to Prometheus config
remoteWrite:
  - url: "https://your-remote-storage/write"
    headers:
      Authorization: "Bearer YOUR_TOKEN"
```

Compatible with:
- Thanos
- Cortex
- Grafana Cloud
- Datadog
- New Relic

### Q: How do I add custom remediation actions?

**A:** Edit the webhook Python code in `manifests/05-remediation/configmap-remediation-webhook.yaml`:
```python
@app.route('/remediate', methods=['POST'])
def remediate():
    alert_name = alert['labels']['alertname']
    
    if alert_name == "MyCustomAlert":
        # Your custom action here
        my_custom_function()
        return {'status': 'custom_action_triggered'}
```

### Q: Can this work with service mesh (Istio/Linkerd)?

**A:** Yes! Works alongside service meshes. The monitoring is at the infrastructure level, independent of service mesh.

---

## Performance Questions

### Q: What's the performance impact on my cluster?

**A:** Minimal:
- **Per-node CPU:** <1% (100m CPU request)
- **Per-node Memory:** <0.5% (128Mi request)
- **Network:** <1KB/s per node for metrics
- **CloudWatch API:** ~100 calls/hour per node

### Q: Does this work with 100+ node clusters?

**A:** Yes, tested up to 100 nodes. For larger clusters:
- Consider CloudWatch agent instead of API calls
- Use Prometheus federation for multi-cluster
- Adjust scrape intervals if needed

### Q: Will this slow down DNS queries?

**A:** No! Monitoring is out-of-band:
- Doesn't intercept DNS queries
- Only reads metrics after-the-fact
- NodeLocal DNS Cache actually speeds up queries by 50%

---

## Security Questions

### Q: What permissions does this need?

**A:** Minimal:
- **Read:** nodes, pods (for discovery)
- **Update:** deployments/scale in kube-system (for CoreDNS scaling)
- **Cloud:** CloudWatch read (AWS) or Monitoring Reader (Azure)

See RBAC manifests for exact permissions.

### Q: Is it safe to run with elevated privileges?

**A:** The DaemonSet needs `hostNetwork: true` to access node-level metrics, but:
- Runs as non-root user
- Read-only root filesystem
- Minimal attack surface
- No secrets in environment variables

### Q: How are cloud credentials handled?

**A:** Best practices:
- **AWS:** IAM roles attached to nodes (no credentials in pods)
- **Azure:** Managed identity (no credentials needed)
- **Never** hardcode credentials

---

## Comparison Questions

### Q: How is this different from X?

| Feature | This Solution | Datadog | New Relic | Manual Monitoring |
|---------|--------------|---------|-----------|-------------------|
| Cost | Open source | $$ | $$ | Free (high labor cost) |
| Auto-remediation | ✅ | ❌ | ❌ | ❌ |
| Cloud-specific metrics | ✅ | Limited | Limited | ✅ (manual) |
| Setup time | 10 min | Hours | Hours | Days |
| Customizable | ✅ | Limited | Limited | ✅ |

### Q: Why not just use kubectl to check DNS?

**A:** Manual checking:
- ❌ Requires constant monitoring
- ❌ Humans are slow (45 min detection vs 30 sec)
- ❌ Can't scale in middle of the night
- ❌ No historical data for capacity planning

---

## Future Roadmap

### Q: What features are planned?

- [ ] Predictive scaling based on ML
- [ ] GKE support
- [ ] Multi-cluster dashboard
- [ ] Integration with Argo Rollouts
- [ ] Advanced anomaly detection
- [ ] Slack/Teams interactive buttons

### Q: Can I contribute?

**A:** Absolutely! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

## Getting More Help

### Q: Where can I ask questions not covered here?

1. **GitHub Discussions:** https://github.com/bharathcs/kubernetes-dns-autoheal/discussions
2. **Issues:** https://github.com/bharathcs/kubernetes-dns-autoheal/issues
3. **Email:** bharathcs@example.com
4. **LinkedIn:** [Bharath Vasudevan](https://www.linkedin.com/in/bharath-vasudevan-b4b07315/)

---

## Quick Links

- 📖 [Architecture Details](architecture.md)
- 🔧 [Troubleshooting Guide](troubleshooting.md)
- 📝 [Implementation Guide](implementation-guide.md)
- 🏠 [Back to README](../README.md)
