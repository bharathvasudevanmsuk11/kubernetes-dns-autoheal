# Runbook: Conntrack Exhausted

## Alert Details

**Alert Name:** ConntrackExhausted  
**Severity:** Warning (Yellow)  
**Team:** Infrastructure  
**Auto-Remediation:** No (manual intervention required)

---

## Summary

The connection tracking (conntrack) table on one or more nodes is full. This limits the number of concurrent network connections and can cause connection failures.

**Unlike DNS throttling, this cannot be auto-remediated** and requires instance-level changes.

---

## Symptoms

- Alert: `kubernetes_dns_conntrack_allowance_exceeded > 0` for 5+ minutes
- New connection attempts fail
- Applications report "connection timeout" or "connection refused"
- Existing connections may work, but new ones fail
- Random connection drops

---

## Understanding Conntrack

**What is it?**  
Conntrack (connection tracking) is a Linux kernel feature that tracks all network connections. It has a maximum table size based on instance type.

**Limits by Instance Type (AWS):**
- t3.medium: ~32,768 connections
- m5.large: ~65,536 connections
- c5.xlarge: ~131,072 connections

**When does it fill up?**
- High connection churn (many short-lived connections)
- Connection leaks (not closing properly)
- Too many concurrent connections for instance size

---

## Immediate Actions

### Step 1: Identify Affected Nodes
```bash
# Query Prometheus
# kubernetes_dns_conntrack_allowance_exceeded > 0

# Or check DaemonSet logs
kubectl logs -n monitoring -l app=dns-throttle-monitor | grep conntrack
```

### Step 2: Check Current Conntrack Status
```bash
# SSH to affected node or use kubectl exec
# Get conntrack current/max
sudo sysctl net.netfilter.nf_conntrack_count
sudo sysctl net.netfilter.nf_conntrack_max

# Show ratio
echo "Usage: $(cat /proc/sys/net/netfilter/nf_conntrack_count) / $(cat /proc/sys/net/netfilter/nf_conntrack_max)"
```

### Step 3: Identify Heavy Connection Users
```bash
# On the affected node
# Show top connection users by pod
sudo conntrack -L | grep -oP 'src=\K[^ ]+' | sort | uniq -c | sort -rn | head -20

# Or use netstat
sudo netstat -anp | grep ESTABLISHED | awk '{print $7}' | cut -d'/' -f1 | sort | uniq -c | sort -rn
```

---

## Short-Term Mitigation

### Option 1: Increase Conntrack Table Size (Temporary)
```bash
# SSH to node
# Increase table size (temporary until reboot)
sudo sysctl -w net.netfilter.nf_conntrack_max=262144

# Verify
sudo sysctl net.netfilter.nf_conntrack_max

# Note: This is temporary and will reset on reboot
# Not recommended for production - upgrade instance instead
```

### Option 2: Reduce Connection Timeout
```bash
# Decrease timeout for established connections
sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=3600

# Default is 432000 (5 days), setting to 3600 (1 hour)
```

### Option 3: Cordon and Drain Node
```bash
# Prevent new pods from scheduling
kubectl cordon NODE_NAME

# Drain existing pods (gracefully)
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Wait for pods to move to other nodes
# This gives time to replace the node
```

---

## Long-Term Solutions

### Solution 1: Upgrade Instance Type (Recommended)

**For AWS EKS:**
```bash
# Create new node group with larger instance type
eksctl create nodegroup \
  --cluster=CLUSTER_NAME \
  --name=workers-m5-xlarge \
  --node-type=m5.xlarge \
  --nodes=3 \
  --nodes-min=2 \
  --nodes-max=5

# Cordon old nodes
kubectl cordon -l node.kubernetes.io/instance-type=t3.medium

# Drain old nodes
for node in $(kubectl get nodes -l node.kubernetes.io/instance-type=t3.medium -o name); do
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data
done

# Delete old node group
eksctl delete nodegroup \
  --cluster=CLUSTER_NAME \
  --name=OLD_NODE_GROUP
```

**For Azure AKS:**
```bash
# Add new node pool with larger VMs
az aks nodepool add \
  --cluster-name CLUSTER_NAME \
  --name largenodes \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --resource-group RESOURCE_GROUP

# Cordon and drain old nodes
# Delete old node pool
az aks nodepool delete \
  --cluster-name CLUSTER_NAME \
  --name oldnodes \
  --resource-group RESOURCE_GROUP
```

### Solution 2: Fix Application Connection Leaks

**Identify leaking applications:**
```bash
# Find pods with high connection counts
kubectl exec -it POD_NAME -- netstat -an | grep ESTABLISHED | wc -l

# Check for unclosed connections
kubectl exec -it POD_NAME -- netstat -an | grep TIME_WAIT | wc -l
```

**Common issues:**
- Database connections not properly closed
- HTTP clients not reusing connections
- Missing connection pooling
- Leaked file descriptors

**Fix examples:**
```python
# Python - Use connection pooling
import psycopg2.pool
pool = psycopg2.pool.SimpleConnectionPool(minconn=1, maxconn=10, ...)

# Python - Use context managers
with requests.Session() as session:
    response = session.get(url)
```
```java
// Java - Use connection pooling
HikariConfig config = new HikariConfig();
config.setMaximumPoolSize(10);
HikariDataSource ds = new HikariDataSource(config);
```

### Solution 3: Implement Connection Pooling

For applications making many outbound connections:
```yaml
# Example: Configure connection pooling in deployment
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: DB_POOL_SIZE
          value: "10"  # Limit concurrent DB connections
        - name: HTTP_MAX_CONNS
          value: "100"  # Limit HTTP connections
        - name: KEEP_ALIVE_TIMEOUT
          value: "30"   # Reuse connections
```

---

## Root Cause Analysis

### Common Causes

#### 1. Microservices with High Fan-Out

**Problem:** One service calls 10+ downstream services  
**Impact:** Each request = 10+ connections  
**Solution:**
- Implement connection pooling
- Use keep-alive for HTTP
- Consider service mesh (Istio/Linkerd)

#### 2. Database Connection Leaks

**Problem:** Connections not closed after use  
**Impact:** Conntrack fills with stale DB connections  
**Solution:**
- Use connection pooling (e.g., HikariCP, pgbouncer)
- Always use try-with-resources/context managers
- Monitor connection usage

#### 3. Excessive Health Checks

**Problem:** Too frequent health checks to too many endpoints  
**Impact:** Thousands of connections for health checks  
**Solution:**
- Reduce health check frequency
- Use liveness/readiness probes wisely
- Consider passive health checks

#### 4. Missing Keep-Alive

**Problem:** HTTP clients create new connection per request  
**Impact:** High connection churn  
**Solution:**
```python
# Python requests - enable keep-alive
session = requests.Session()
adapter = requests.adapters.HTTPAdapter(pool_maxsize=10)
session.mount('http://', adapter)
```

---

## Verification

After implementing fixes:
```bash
# 1. Check conntrack usage decreased
sudo sysctl net.netfilter.nf_conntrack_count

# Should be well below max

# 2. Monitor in Prometheus
# Query: kubernetes_dns_conntrack_allowance_exceeded
# Should return to 0

# 3. Check application connection counts
kubectl exec POD_NAME -- netstat -an | grep ESTABLISHED | wc -l

# Should be stable, not growing

# 4. Verify no connection errors in logs
kubectl logs POD_NAME | grep -i "connection\|timeout"
```

---

## Prevention

### Infrastructure Level

- [ ] Use instance types with adequate conntrack limits
- [ ] Minimum recommendation: m5.large or equivalent (65k connections)
- [ ] Monitor conntrack usage as part of node health
- [ ] Set up alerts for conntrack > 80% utilization

### Application Level

- [ ] Implement connection pooling for all database connections
- [ ] Use HTTP keep-alive for REST APIs
- [ ] Close connections explicitly in code
- [ ] Add connection metrics to application dashboards
- [ ] Code review checklist includes connection management

### Kubernetes Level

- [ ] Use service mesh for automatic connection management
- [ ] Configure pod resource limits to prevent runaway connections
- [ ] Use NetworkPolicies to limit connection scope
- [ ] Regular audit of health check configurations

---

## Monitoring

Add these to your dashboards:
```promql
# Conntrack usage percentage
(node_nf_conntrack_entries / node_nf_conntrack_entries_limit) * 100

# Conntrack usage by node
kubernetes_dns_conntrack_allowance_available

# Rate of new connections
rate(node_nf_conntrack_entries[5m])
```

---

## Escalation

### Escalate to Platform Team if:

- Multiple nodes affected
- Chronic issue despite application fixes
- Instance type upgrades needed

### Escalate to Development Team if:

- Specific application identified as cause
- Code changes required
- Connection pooling needs implementation

---

## Related Documentation

- [AWS EC2 Instance Network Performance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/general-purpose-instances.html)
- [Kubernetes Best Practices - Connection Management](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Linux Conntrack Documentation](https://www.kernel.org/doc/Documentation/networking/nf_conntrack-sysctl.txt)

---

## Related Runbooks

- [DNS Throttling Warning](dns-throttling-warning.md)
- [DNS Throttling Critical](dns-throttling-critical.md)
- [Bandwidth Saturation](bandwidth-saturation.md)

---

**Last Updated:** January 2026  
**Version:** 1.0.0  
**Owner:** Infrastructure Team
