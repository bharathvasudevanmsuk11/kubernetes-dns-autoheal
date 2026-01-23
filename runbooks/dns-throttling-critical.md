# Runbook: DNS Throttling Critical

## Alert Details

**Alert Name:** DNSThrottlingCritical  
**Severity:** Critical (Red)  
**Team:** SRE  
**Escalation:** Manager  
**Auto-Remediation:** Yes (scales CoreDNS to 6 replicas)  
**PagerDuty:** Enabled

---

## ⚠️ CRITICAL ALERT - IMMEDIATE ACTION REQUIRED

This is a **production-impacting** issue. DNS throttling is severe and likely causing service degradation.

---

## Summary

DNS packets are being dropped at a high rate (>100 packets). This indicates severe network throttling that **will impact user-facing services**.

**Auto-remediation has scaled CoreDNS to 6 replicas, but manual intervention may be required.**

---

## Immediate Actions (First 5 Minutes)

### 1. Acknowledge Alert
```bash
# In PagerDuty: Click "Acknowledge"
# In Slack: React with 👀 emoji to indicate you're handling it
```

### 2. Assess Impact
```bash
# Check for service degradation
kubectl get pods --all-namespaces | grep -E '(Error|CrashLoop|Pending)'

# Check recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Look for DNS-related failures
```

### 3. Verify Auto-Remediation
```bash
# Check CoreDNS scaling
kubectl get deployment coredns -n kube-system

# Expected: 6 replicas
# If not at 6 replicas, manually scale:
kubectl scale deployment coredns -n kube-system --replicas=6

# Verify all pods are running
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### 4. Check Throttling Status
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Query: kubernetes_dns_linklocal_allowance_exceeded
# Check current value and trend
```

---

## Emergency Remediation

If auto-scaling didn't resolve the issue:

### Step 1: Maximum CoreDNS Scaling
```bash
# Scale CoreDNS to maximum
kubectl scale deployment coredns -n kube-system --replicas=10

# Wait 2 minutes
sleep 120

# Verify status
kubectl get deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```

### Step 2: Add Emergency Node Capacity

**For AWS EKS:**
```bash
# Add nodes immediately
eksctl scale nodegroup \
  --cluster=CLUSTER_NAME \
  --name=NODE_GROUP_NAME \
  --nodes=5 \
  --nodes-min=3 \
  --nodes-max=10

# Or using AWS CLI
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name ASG_NAME \
  --desired-capacity 5
```

**For Azure AKS:**
```bash
# Scale node pool
az aks nodepool scale \
  --cluster-name CLUSTER_NAME \
  --name NODE_POOL_NAME \
  --node-count 5 \
  --resource-group RESOURCE_GROUP
```

### Step 3: Deploy NodeLocal DNS (Emergency)

If not already deployed:
```bash
# Deploy immediately
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

# Verify deployment
kubectl get daemonset -n kube-system node-local-dns

# Wait for all pods to be running
kubectl wait --for=condition=ready pod \
  -l k8s-app=node-local-dns \
  -n kube-system \
  --timeout=300s
```

---

## Detailed Investigation

### Identify Affected Nodes
```bash
# Query Prometheus for nodes with high throttling
# kubernetes_dns_linklocal_allowance_exceeded > 100

# Or check DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=100 | grep -i exceeded
```

### Check Node Health
```bash
# For each affected node
kubectl describe node NODE_NAME

# Look for:
# - Conditions: MemoryPressure, DiskPressure, PIDPressure
# - Capacity vs Allocatable resources
# - Number of pods running
```

### Analyze DNS Query Patterns
```bash
# Port-forward to CoreDNS pod
kubectl port-forward -n kube-system POD_NAME 9153:9153 &

# Check CoreDNS metrics
curl localhost:9153/metrics | grep coredns_dns_request_count_total

# Look for:
# - Total request rate
# - Request types (A, AAAA, SRV)
# - Response codes
```

### Identify Heavy DNS Users
```bash
# Get all pods on affected node
kubectl get pods --all-namespaces -o wide \
  --field-selector spec.nodeName=NODE_NAME

# Check logs for DNS errors
for pod in $(kubectl get pods -n NAMESPACE -o name); do
  echo "=== $pod ==="
  kubectl logs $pod -n NAMESPACE --tail=50 | grep -i "dns\|timeout\|resolve"
done
```

---

## Root Cause Scenarios

### Scenario 1: DDoS or Traffic Spike

**Symptoms:**
- Sudden spike in DNS queries
- Multiple nodes affected
- Recent deployment or traffic change

**Actions:**
```bash
# Check recent deployments
kubectl rollout history deployment -n NAMESPACE

# Check replica counts
kubectl get deployment -A | grep -v "1/1"

# Consider rolling back recent changes
kubectl rollout undo deployment DEPLOYMENT_NAME -n NAMESPACE
```

### Scenario 2: Application Bug (DNS Loop)

**Symptoms:**
- Single service/pod causing high DNS load
- Exponential query growth
- Logs show repeated DNS lookups

**Actions:**
```bash
# Identify problematic pod
# Check application logs for DNS patterns

# Scale down problematic deployment
kubectl scale deployment PROBLEMATIC_APP -n NAMESPACE --replicas=0

# Wait for throttling to decrease
# Fix application code before scaling back up
```

### Scenario 3: Infrastructure Capacity Issue

**Symptoms:**
- All nodes near capacity
- Chronic throttling across cluster
- Instance types at network limits

**Actions:**
```bash
# Immediate: Add more nodes (see Emergency Remediation)
# Short-term: Upgrade instance types
# Long-term: Capacity planning review
```

---

## Communication

### Internal Communication

**Post in Slack #incidents:**

🚨 INCIDENT: DNS Throttling Critical
Status: INVESTIGATING
Impact: Potential service degradation
Affected: [List affected services/namespaces]
Actions Taken:

CoreDNS scaled to 6 replicas
Investigating root cause
[Any other actions]

Next Update: [Time, e.g., in 10 minutes]
Incident Commander: @your-name

### Update PagerDuty
Status: Acknowledged
Note: CoreDNS scaled, investigating affected nodes
ETA: 15 minutes for initial assessment

### Escalate to Management

If service degradation confirmed:

**Email to engineering-manager@company.com:**
Subject: [CRITICAL] Production DNS Throttling Incident
Summary:

Critical DNS throttling detected at [TIME]
Auto-remediation triggered (CoreDNS scaled to 6 replicas)
Investigating impact on user-facing services
Current status: [INVESTIGATING/MITIGATING/RESOLVED]

Actions Taken:

Scaled CoreDNS to maximum capacity
[Other actions]

Expected Resolution: [TIME ESTIMATE]
Incident Commander: [YOUR NAME]

---

## Verification After Remediation

### 1. Metrics Check
```bash
# Throttling returned to zero
# Query: kubernetes_dns_linklocal_allowance_exceeded
# Should show 0 across all nodes

# CoreDNS healthy
kubectl get pods -n kube-system -l k8s-app=kube-dns
# All Running, no crashes
```

### 2. Service Health Check
```bash
# Test DNS resolution
kubectl run test-dns --image=busybox --rm -it --restart=Never -- \
  nslookup kubernetes.default

# Check application pods
kubectl get pods --all-namespaces | grep -v Running

# Verify no new errors in logs
```

### 3. User Impact Assessment
```bash
# Check application error rates (if using APM)
# Review user-facing metrics
# Confirm no customer reports of issues
```

---

## Post-Incident Review

**Schedule within 24 hours**

### Required Attendees:
- Incident Commander
- SRE Team
- Platform Team
- Service Owners (if affected)

### Agenda:
1. Timeline of events
2. Root cause analysis
3. Effectiveness of auto-remediation
4. Action items to prevent recurrence
5. Documentation updates

### Action Items Template:

 Update alert thresholds if needed
 Review instance type sizing
 Deploy NodeLocal DNS to all clusters
 Add DNS load testing to CI/CD
 Update capacity planning
 Train team on this runbook


---

## Prevention

### Immediate (Today)

- [ ] Ensure NodeLocal DNS deployed on all clusters
- [ ] Verify CoreDNS autoscaler max = 10 (not default)
- [ ] Add monitoring for DNS query rates per namespace

### Short-term (This Week)

- [ ] Review all applications for DNS caching
- [ ] Implement connection pooling where missing
- [ ] Add DNS health checks to smoke tests
- [ ] Update instance type recommendations

### Long-term (This Month)

- [ ] Capacity planning review
- [ ] Consider service mesh for DNS caching
- [ ] Implement predictive scaling based on traffic patterns
- [ ] Add DNS performance to SLOs

---

## Related Runbooks

- [DNS Throttling Warning](dns-throttling-warning.md)
- [Conntrack Exhausted](conntrack-exhausted.md)
- [Bandwidth Saturation](bandwidth-saturation.md)

---

## Escalation Paths

| Time | Action | Contact |
|------|--------|---------|
| 0 min | Acknowledge in PagerDuty | SRE On-Call |
| 5 min | Start remediation | SRE On-Call |
| 15 min | Escalate if not improving | SRE Lead |
| 30 min | Major incident declared | Engineering Manager |
| 1 hour | Executive notification | VP Engineering |

---

## Reference Links

- **Grafana Dashboard:** http://your-grafana/d/dns-throttling
- **Prometheus:** http://your-prometheus:9090
- **Alertmanager:** http://your-alertmanager:9093
- **Incident Log:** [Link to incident tracking system]

---

**Last Updated:** January 2026  
**Version:** 1.0.0  
**Owner:** SRE Team  
**Reviewed By:** Engineering Manager
