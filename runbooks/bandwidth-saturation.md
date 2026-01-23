# Runbook: Bandwidth Saturation

## Alert Details

**Alert Name:** BandwidthSaturation  
**Severity:** Warning (Yellow)  
**Team:** Network/Infrastructure  
**Auto-Remediation:** No (requires scaling)

---

## Summary

One or more nodes have exceeded their network bandwidth allowance. This causes packet loss, increased latency, and potential service degradation.

---

## Symptoms

- Alert: `(kubernetes_dns_bw_in_allowance_exceeded + kubernetes_dns_bw_out_allowance_exceeded) > 0` for 3+ minutes
- High latency in network calls
- Packet loss
- Timeouts in inter-service communication
- Slow data transfers

---

## Understanding Network Bandwidth Limits

**AWS Instance Bandwidth Examples:**
| Instance Type | Baseline | Burst | Network Performance |
|---------------|----------|-------|---------------------|
| t3.medium | 5 Gbps | Up to 5 Gbps | Up to 5 Gigabit |
| m5.large | 10 Gbps | Up to 10 Gbps | Up to 10 Gigabit |
| m5.xlarge | 10 Gbps | Up to 10 Gbps | Up to 10 Gigabit |
| m5.2xlarge | 10 Gbps | Up to 10 Gbps | Up to 10 Gigabit |
| m5.4xlarge | 10 Gbps | Up to 10 Gbps | 10 Gigabit |
| m5.8xlarge | 10 Gbps | 10 Gbps | 10 Gigabit |

**Azure VM Bandwidth Examples:**
| VM Size | Expected Network Bandwidth |
|---------|----------------------------|
| Standard_D2s_v3 | 1000 Mbps |
| Standard_D4s_v3 | 2000 Mbps |
| Standard_D8s_v3 | 4000 Mbps |
| Standard_D16s_v3 | 8000 Mbps |

---

# Immediate Actions

### Step 1: Identify Affected Nodes
```bash
# Query Prometheus for nodes exceeding bandwidth
# kubernetes_dns_bw_in_allowance_exceeded > 0
# kubernetes_dns_bw_out_allowance_exceeded > 0

# Or check logs
kubectl logs -n monitoring -l app=dns-throttle-monitor | grep -i bandwidth
```

### Step 2: Assess Bandwidth Usage
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Query bandwidth metrics
# - kubernetes_dns_bw_in_allowance_exceeded (inbound)
# - kubernetes_dns_bw_out_allowance_exceeded (outbound)

# Check which direction is saturated
```

### Step 3: Identify High-Bandwidth Workloads
```bash
# Get all pods on affected node
kubectl get pods --all-namespaces -o wide \
  --field-selector spec.nodeName=NODE_NAME

# Check pod network usage (if metrics-server installed)
kubectl top pods -n NAMESPACE --sort-by=memory

# Look for:
# - Data processing workloads
# - File transfers
# - Video streaming
# - Large API responses
```

### Step 4: Check for Network Issues
```bash
# SSH to node or kubectl exec
# Check network interface statistics
ip -s link show

# Look for:
# - TX/RX errors
# - Dropped packets
# - Overruns
```

---

## Short-Term Mitigation

### Option 1: Scale Horizontally (Recommended)
```bash
# Add more nodes to distribute load
# For AWS EKS:
eksctl scale nodegroup \
  --cluster=CLUSTER_NAME \
  --name=NODE_GROUP \
  --nodes=5

# For Azure AKS:
az aks nodepool scale \
  --cluster-name CLUSTER_NAME \
  --name POOL_NAME \
  --node-count 5 \
  --resource-group RESOURCE_GROUP

# Wait for new nodes to join
kubectl get nodes -w
```

### Option 2: Move High-Bandwidth Workloads
```bash
# Cordon the saturated node
kubectl cordon NODE_NAME

# Identify pods to move
kubectl get pods -n NAMESPACE -o wide --field-selector spec.nodeName=NODE_NAME

# Delete pods to reschedule on other nodes
kubectl delete pod POD_NAME -n NAMESPACE

# Pods will be recreated on nodes with capacity
```

### Option 3: Implement Rate Limiting

If a specific application is causing saturation:
```yaml
# Add resource limits to deployment
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          limits:
            # Limit network bandwidth (if supported by CNI)
            kubernetes.io/ingress-bandwidth: 10M
            kubernetes.io/egress-bandwidth: 10M
```

---

## Long-Term Solutions

### Solution 1: Upgrade to Higher-Bandwidth Instances

**For AWS EKS:**
```bash
# Create node group with higher bandwidth instances
eksctl create nodegroup \
  --cluster=CLUSTER_NAME \
  --name=high-bandwidth-nodes \
  --node-type=m5.4xlarge \
  --nodes=3 \
  --nodes-min=2 \
  --nodes-max=5

# Migrate workloads
# Cordon and drain old nodes
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Delete old node group
eksctl delete nodegroup --cluster=CLUSTER_NAME --name=OLD_GROUP
```

**For Azure AKS:**
```bash
# Add new high-bandwidth node pool
az aks nodepool add \
  --cluster-name CLUSTER_NAME \
  --name highbw \
  --node-count 3 \
  --node-vm-size Standard_D16s_v3 \
  --resource-group RESOURCE_GROUP

# Migrate and delete old pool
```

### Solution 2: Optimize Application Network Usage

**Identify bandwidth-intensive operations:**
```bash
# Check pod network I/O
kubectl exec POD_NAME -- cat /sys/class/net/eth0/statistics/rx_bytes
kubectl exec POD_NAME -- cat /sys/class/net/eth0/statistics/tx_bytes

# Monitor over time to identify patterns
```

**Common optimizations:**

1. **Compress Data Transfers**
```python
# Python example - use gzip compression
import gzip
import requests

response = requests.get(url, headers={'Accept-Encoding': 'gzip'})
```

2. **Implement Caching**
```yaml
# Add Redis cache to reduce API calls
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cache
spec:
  template:
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
```

3. **Use CDN for Static Content**
- Move images/videos to S3 + CloudFront
- Reduce cluster egress bandwidth
- Improve user experience

4. **Batch API Requests**
```javascript
// Instead of:
for (item of items) {
  await api.post('/item', item);  // 1000 requests
}

// Do:
await api.post('/items/batch', items);  // 1 request
```

### Solution 3: Implement Network Policies

Limit unnecessary cross-namespace traffic:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: limit-bandwidth-apps
  namespace: high-bandwidth
spec:
  podSelector:
    matchLabels:
      app: data-processor
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: storage
    ports:
    - protocol: TCP
      port: 3306
```

### Solution 4: Use Node Affinity for Bandwidth-Heavy Workloads
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: high-bandwidth-app
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values:
                - m5.4xlarge  # High bandwidth instances
                - c5.4xlarge
```

---

## Root Cause Analysis

### Common Causes

#### 1. Large Data Transfers

**Symptoms:**
- Periodic bandwidth spikes
- Batch processing jobs
- Data sync operations

**Examples:**
- Database backups
- Log aggregation
- ETL pipelines

**Solution:**
```yaml
# Schedule during off-peak hours
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-sync
spec:
  schedule: "0 2 * * *"  # 2 AM
```

#### 2. Microservices Communication Overhead

**Symptoms:**
- High inter-service traffic
- Many small requests
- Chatty microservices

**Solution:**
- Implement service mesh (Istio/Linkerd)
- Use gRPC instead of REST
- Batch requests where possible
- Implement caching

#### 3. External API Calls

**Symptoms:**
- High egress bandwidth
- Many third-party API calls
- Large response payloads

**Solution:**
```python
# Cache external API responses
from functools import lru_cache
import requests

@lru_cache(maxsize=1000)
def get_external_data(api_key, endpoint):
    return requests.get(f"https://api.example.com/{endpoint}",
                       headers={'Authorization': api_key})
```

#### 4. Missing Compression

**Symptoms:**
- Large uncompressed data transfers
- High bandwidth for API responses

**Solution:**
```nginx
# Enable gzip compression in ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      gzip on;
      gzip_types text/plain application/json;
```

#### 5. Video/Image Processing

**Symptoms:**
- Very high bandwidth usage
- Large file uploads/downloads

**Solution:**
- Use object storage (S3, Azure Blob)
- Implement CDN
- Process on dedicated node pool
- Use pre-signed URLs for direct upload

---

## Verification

After implementing fixes:
```bash
# 1. Check bandwidth metrics in Prometheus
# Query: kubernetes_dns_bw_in_allowance_exceeded
# Query: kubernetes_dns_bw_out_allowance_exceeded
# Both should be 0

# 2. Monitor node network usage
kubectl top nodes

# 3. Check for packet drops
# SSH to node
ip -s link show | grep -A 3 eth0

# 4. Verify application performance
# Check latency metrics
# No timeout errors in logs
```

---

## Prevention

### Infrastructure Level

- [ ] Right-size instance types for workload
- [ ] Use instance types with "Up to 25 Gigabit" or higher for data-intensive apps
- [ ] Implement node pools per workload type
- [ ] Monitor bandwidth utilization as part of capacity planning

### Application Level

- [ ] Enable compression for all API responses
- [ ] Implement caching (Redis, Memcached)
- [ ] Use CDN for static content
- [ ] Optimize database queries to reduce data transfer
- [ ] Batch API requests where possible

### Kubernetes Level

- [ ] Use NetworkPolicies to limit unnecessary traffic
- [ ] Implement service mesh for traffic management
- [ ] Use node affinity for bandwidth-intensive workloads
- [ ] Schedule bandwidth-heavy jobs during off-peak hours

---

## Monitoring

Add these to your dashboards:
```promql
# Bandwidth usage
kubernetes_dns_bw_in_allowance_exceeded + kubernetes_dns_bw_out_allowance_exceeded

# Network I/O per node
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])
```

**Set alerts for:**
- Bandwidth usage > 80% of instance limit
- Consistent bandwidth spikes
- Network errors increasing

---

## Capacity Planning

### Monthly Review
```bash
# Calculate peak bandwidth usage
# Query in Prometheus (last 30 days):
max_over_time(
  rate(node_network_transmit_bytes_total[5m])[30d:]
)

# Compare against instance limits
# Plan capacity increases if consistently > 70%
```

### Growth Projections
Current Usage: [X] Gbps
Instance Limit: [Y] Gbps
Utilization: [X/Y]%
Expected Growth: [Z]% per quarter
Time to Saturation: [Calculate]
Recommendation:

If < 6 months: Upgrade immediately
If < 12 months: Plan upgrade
If > 12 months: Continue monitoring


---

## Escalation

### Escalate to Network Team if:

- Multiple nodes affected
- Unusual traffic patterns detected
- Possible DDoS or security incident

### Escalate to Development Team if:

- Specific application causing issue
- Code optimization needed
- Architecture review required

### Escalate to Infrastructure Team if:

- Instance type upgrades needed
- Multi-region architecture consideration
- Network topology changes required

---

## Cost Considerations

### AWS Data Transfer Costs
Intra-region (same AZ): Free
Intra-region (different AZ): $0.01/GB
Inter-region: $0.02/GB
To Internet: $0.09/GB (first 10 TB)

**Optimization strategies:**
- Keep communicating services in same AZ
- Use VPC endpoints for AWS services
- Implement caching to reduce data transfer

### Azure Data Transfer Costs
Intra-region: Free
Inter-region: $0.02/GB
To Internet: $0.087/GB (first 5 GB free)

---

## Related Runbooks

- [DNS Throttling Warning](dns-throttling-warning.md)
- [DNS Throttling Critical](dns-throttling-critical.md)
- [Conntrack Exhausted](conntrack-exhausted.md)

---

## Additional Resources

- [AWS EC2 Network Performance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-network-bandwidth.html)
- [Azure VM Network Bandwidth](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-machine-network-throughput)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

**Last Updated:** January 2026  
**Version:** 1.0.0  
**Owner:** Network/Infrastructure Team

📁 How to Add These Files
bashcd kubernetes-dns-autoheal

# Create runbooks directory
mkdir -p runbooks

# Create each runbook file
touch runbooks/dns-throttling-warning.md
touch runbooks/dns-throttling-critical.md
touch runbooks/conntrack-exhausted.md
touch runbooks/bandwidth-saturation.md

# Copy content from above into each file

# Commit
git add runbooks/
git commit -m "Add complete incident response runbooks

- DNS Throttling Warning runbook with auto-remediation steps
- DNS Throttling Critical runbook with emergency procedures
- Conntrack Exhausted runbook with mitigation strategies
- Bandwidth Saturation runbook with optimization guide

All runbooks include:
- Immediate action steps
- Investigation procedures
- Root cause analysis
- Prevention strategies
- Escalation paths"

git push origin main
