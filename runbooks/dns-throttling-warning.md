# Runbook: DNS Throttling Warning

## Alert Details

**Alert Name:** DNSThrottlingWarning  
**Severity:** Warning (Yellow)  
**Team:** SRE  
**Auto-Remediation:** Yes (scales CoreDNS to 4 replicas)

---

## Summary

DNS queries to link-local addresses are being throttled on one or more nodes. This indicates the instance is approaching network packet limits. Auto-remediation has been triggered to scale CoreDNS.

---

## Symptoms

- Alert: `kubernetes_dns_linklocal_allowance_exceeded > 0` for 2+ minutes
- Intermittent DNS resolution failures
- Possible application timeouts
- Pods may show "timeout waiting for DNS" errors

---

## Auto-Remediation Actions

✅ **Automatic actions already taken:**
1. CoreDNS scaled to 4 replicas
2. Slack notification sent to #sre-alerts
3. Incident logged

**You should:**
- Monitor the situation for next 5 minutes
- Verify auto-remediation resolved the issue
- Investigate root cause if pattern repeats

---

## Investigation Steps

### Step 1: Verify Current Status
```bash
# Check current throttling metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Open Prometheus: http://localhost:9090
# Query: kubernetes_dns_linklocal_allowance_exceeded
# Check if value is decreasing
```

### Step 2: Check CoreDNS Status
```bash
# Verify CoreDNS scaled up
kubectl get deployment coredns -n kube-system

# Expected: 4 replicas running
# NAME      READY   UP-TO-DATE   AVAILABLE
# coredns   4/4     4            4

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# All pods should be Running
```

### Step 3: Check Node-Level Metrics
```bash
# Identify affected nodes
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Query in Prometheus:
# kubernetes_dns_linklocal_allowance_exceeded > 0

# Note the instance IDs showing non-zero values
```

### Step 4: Verify NodeLocal DNS Cache
```bash
# Check if NodeLocal DNS is deployed
kubectl get daemonset -n kube-system node-local-dns

# Expected: One pod per node
# If not deployed, this is the root cause
```

### Step 5: Check Application DNS Query Patterns
```bash
# Find pods making excessive DNS queries
# SSH to affected node (or use kubectl exec)

# Check DNS query rate
sudo tcpdump -i any -n port 53 -c 100

# Look for patterns:
# - Same pod querying repeatedly
# - DNS loops (A queries B, B queries A)
# - Missing DNS caching in applications
```

---

## Manual Remediation (if auto-remediation insufficient)

### Option 1: Deploy NodeLocal DNS Cache

If not already deployed:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

# Verify deployment
kubectl get daemonset -n kube-system node-local-dns

# This reduces DNS queries to CoreDNS by ~80%
```

### Option 2: Increase CoreDNS Replicas Further
```bash
# Scale to 6 replicas
kubectl scale deployment coredns -n kube-system --replicas=6

# Monitor for 5 minutes
watch kubectl get deployment coredns -n kube-system
```

### Option 3: Investigate Specific Workloads
```bash
# Find pods on affected node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=NODE_NAME

# Check logs for DNS-related errors
kubectl logs POD_NAME -n NAMESPACE | grep -i dns

# Look for:
# - Connection refused
# - Timeout
# - Name resolution failures
```

---

## Root Cause Analysis

Common causes of DNS throttling:

### 1. Missing NodeLocal DNS Cache
**Impact:** Every DNS query hits CoreDNS  
**Solution:** Deploy NodeLocal DNS Cache  
**Prevention:** Include in cluster setup checklist

### 2. Application Not Caching DNS
**Impact:** Repeated queries for same hostname  
**Solution:** Configure application DNS TTL/caching  
**Prevention:** Code review for DNS query patterns

### 3. DNS Query Loops
**Impact:** Exponential query growth  
**Solution:** Fix service discovery configuration  
**Prevention:** Test service dependencies

### 4. Insufficient DNS Capacity
**Impact:** High load on few CoreDNS pods  
**Solution:** Increase min replicas in autoscaler  
**Prevention:** Capacity planning based on cluster size

### 5.
