# Architecture Documentation

## Overview

This document provides detailed architecture information for the Kubernetes DNS Auto-Heal solution.

## System Components

### 1. Monitoring Layer

#### DaemonSet Monitor
- **Purpose:** Collect DNS throttling metrics from every node
- **Implementation:** Runs as privileged DaemonSet with hostNetwork
- **Frequency:** Collects metrics every 60 seconds
- **Output:** Prometheus-formatted metrics

**Key Metrics Collected:**

| Metric | Description | Source |
|--------|-------------|--------|
| `kubernetes_dns_linklocal_allowance_exceeded` | DNS queries dropped | AWS CloudWatch / Azure Monitor |
| `kubernetes_dns_conntrack_allowance_exceeded` | Connection tracking exhausted | Cloud provider metrics |
| `kubernetes_dns_bw_in_allowance_exceeded` | Inbound bandwidth exceeded | Network metrics |
| `kubernetes_dns_bw_out_allowance_exceeded` | Outbound bandwidth exceeded | Network metrics |
| `kubernetes_dns_pps_allowance_exceeded` | Packets per second exceeded | Network metrics |

### 2. Storage & Query Layer

#### Prometheus
- **Purpose:** Time-series database for metrics
- **Retention:** 15 days (configurable)
- **Scrape Interval:** 30 seconds
- **Storage:** Persistent volume (10GB default)

**Configuration:**
```yaml
scrapeInterval: 30s
evaluationInterval: 30s
retention: 15d
```

#### Grafana
- **Purpose:** Visualization and dashboards
- **Dashboards Provided:**
  - DNS Throttling Overview
  - Performance Metrics
  - Alert History
  - Node-level Analysis

### 3. Alerting Layer

#### Alertmanager
- **Purpose:** Alert routing and deduplication
- **Features:**
  - Multi-tier severity routing
  - Grouping and inhibition
  - Silencing capabilities
  - Integration with Slack, PagerDuty, Email

**Alert Routing Tree:**
```
Root
├── severity: critical
│   ├── → PagerDuty (page on-call)
│   └── escalate: manager → Email management
├── severity: warning
│   └── → Slack #sre-alerts
└── default
└── → Remediation Webhook
```
### 4. Auto-Remediation Layer

#### CoreDNS Auto-Scaler
- **Type:** Cluster Proportional Autoscaler
- **Algorithm:** Linear scaling based on nodes and cores
- **Parameters:**
  - `coresPerReplica`: 256
  - `nodesPerReplica`: 16
  - `min`: 2
  - `max`: 10

**Scaling Formula:**
```
replicas = max(min, min(max,
ceil(nodes / nodesPerReplica) +
ceil(cores / coresPerReplica)
))
```
#### Remediation Webhook
- **Language:** Python 3.11 + Flask
- **Purpose:** Execute automated responses to alerts
- **Capabilities:**
  - Scale CoreDNS deployment
  - Log incidents
  - Trigger external systems
  - Create tickets (future)

**Decision Matrix:**

| Alert | Auto-Remediation | Escalation |
|-------|------------------|------------|
| DNSThrottlingWarning | Scale to 4 replicas | Slack notification |
| DNSThrottlingCritical | Scale to 6 replicas | PagerDuty page |
| ConntrackExhausted | Log only | Create ticket |

#### NodeLocal DNS Cache
- **Purpose:** Reduce DNS queries to CoreDNS by 80%
- **Implementation:** DaemonSet running on each node
- **Cache Address:** 169.254.20.10
- **Upstream:** CoreDNS cluster IP

---

## Data Flow

```
┌──────────────────────────────────────────────────────────┐
│                     Kubernetes Node                      │
│                                                          │
│  Application Pod                                         │
│       │                                                  │
│       │ DNS Query                                        │
│       ▼                                                  │
│  NodeLocal DNS Cache (169.254.20.10)                     │
│       │                                                  │
│       │ Cache Miss                                       │
│       ▼                                                  │
│  CoreDNS (kube-dns service)                              │
│       │                                                  │
│       │ External Query                                   │
│       ▼                                                  │
│  Cloud DNS (169.254.169.254)  ◄── Throttling happens     │
│                                                          │
│  DaemonSet Monitor                                       │
│       │                                                  │
│       │ Every 60s                                        │
│       ▼                                                  │
│  CloudWatch/Azure Monitor API                            │
│       │                                                  │
│       │ Metrics                                          │
│       ▼                                                  │
│  Node Exporter (port 9100)                               │
└──────────────────────────────────────────────────────────┘
│
│ Scrape (30s)
▼
┌──────────────────────────────────────────────────────────┐
│                    Monitoring Stack                      │
│                                                          │
│  Prometheus                                              │
│       │                                                  │
│       ├──► Grafana (Dashboards)                          │
│       │                                                  │
│       └──► Alertmanager                                  │
│               │                                          │
│               ├──► Slack                                 │
│               ├──► PagerDuty                             │
│               ├──► Email                                 │
│               │                                          │
│               └──► Remediation Webhook                   │
│                       │                                  │
│                       └──► Kubernetes API                │
│                               │                          │
│                               └──► Scale CoreDNS         │
└──────────────────────────────────────────────────────────┘
```
---

## Security Considerations

### RBAC Permissions

**DNS Monitor ServiceAccount:**
- Read: nodes, pods, services
- Purpose: Discover node information

**DNS Autoscaler ServiceAccount:**
- Read: nodes
- Update: deployments/scale
- Purpose: Scale CoreDNS based on cluster size

**Remediation Webhook ServiceAccount:**
- Update: deployments/scale in kube-system
- Purpose: Emergency scaling of CoreDNS

### Network Policies

Recommended network policies (not enforced by default):
```yaml
# Allow Prometheus to scrape metrics
- from:
  - namespaceSelector:
      matchLabels:
        name: monitoring
  ports:
  - protocol: TCP
    port: 9100
```

### Secrets Management

- Alertmanager webhook URLs stored in Kubernetes Secrets
- Cloud credentials via IAM roles (AWS) or Managed Identity (Azure)
- No hardcoded credentials in manifests

---

## Performance Characteristics

### Resource Usage

| Component | CPU (Request) | CPU (Limit) | Memory (Request) | Memory (Limit) |
|-----------|---------------|-------------|------------------|----------------|
| DaemonSet Monitor | 100m | 200m | 128Mi | 256Mi |
| Remediation Webhook | 50m | 100m | 64Mi | 128Mi |
| CoreDNS Autoscaler | 20m | 50m | 32Mi | 64Mi |

### Scalability

- **Nodes:** Tested up to 100 nodes
- **Metrics Collection:** <1% CPU overhead per node
- **Alert Response Time:** <30 seconds from threshold breach to alert
- **Remediation Time:** <2 minutes from alert to scaled CoreDNS

---

## High Availability

### Component HA Strategy

| Component | Replicas | Strategy |
|-----------|----------|----------|
| DaemonSet | 1 per node | Node affinity |
| Prometheus | 1 (HA optional) | StatefulSet with PV |
| Grafana | 1 (HA optional) | Deployment |
| Alertmanager | 3 (recommended) | StatefulSet with gossip |
| Remediation Webhook | 2 | Deployment with anti-affinity |
| CoreDNS Autoscaler | 1 | Deployment with leader election |

### Failure Scenarios

**DaemonSet pod failure:**
- Impact: No metrics from that node
- Mitigation: Kubernetes restarts pod automatically
- Time to recovery: <60 seconds

**Prometheus failure:**
- Impact: No new metrics collected
- Mitigation: Prometheus restarts, historical data in PV
- Time to recovery: <120 seconds

**Webhook failure:**
- Impact: No auto-remediation
- Mitigation: Manual intervention, alerts still fire
- Time to recovery: Manual (alerts notify SRE)

---

## Cloud Provider Specifics

### AWS EKS

**Instance Limits (varies by instance type):**
- t3.medium: 1024 PPS to link-local
- m5.large: 2048 PPS
- c5.xlarge: 4096 PPS

**API Calls:**
- CloudWatch GetMetricStatistics: ~100 calls/hour per node
- Cost: ~$0.01/day per cluster

### Azure AKS

**Metrics Collected:**
- Via Azure Monitor REST API
- Requires Monitoring Reader role
- Rate limits: 12,000 requests/hour per subscription

---

## Future Enhancements

- [ ] Predictive scaling based on historical patterns
- [ ] Integration with cluster autoscaler
- [ ] Multi-cluster federation support
- [ ] Advanced anomaly detection with ML
- [ ] Custom metrics from application layer

---

## References

- [CoreDNS Documentation](https://coredns.io/manual/toc/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
