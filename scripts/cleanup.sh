#!/bin/bash
set -euo pipefail

echo "========================================="
echo "DNS Throttling Solution - Cleanup"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}⚠️  WARNING: This will DELETE all DNS monitoring components.${NC}"
echo ""
read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Removing components..."

# Alerting
echo "Removing alerting configuration..."
kubectl delete -f manifests/06-alerting/ --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✅ Alerting removed${NC}"

# Remediation
echo "Removing remediation webhook..."
kubectl delete -f manifests/05-remediation/ --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✅ Remediation removed${NC}"

# Autoscaling
echo "Removing CoreDNS autoscaler..."
kubectl delete -f manifests/04-autoscaling/ --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✅ Autoscaler removed${NC}"

# Prometheus/Grafana
echo "Removing ServiceMonitor and PrometheusRules..."
kubectl delete -f manifests/03-prometheus-grafana/ --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✅ Prometheus components removed${NC}"

# Monitoring
echo "Removing monitoring DaemonSet..."
kubectl delete -f manifests/02-monitoring/ --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✅ Monitoring removed${NC}"

# NodeLocal DNS Cache (optional)
echo ""
read -p "Remove NodeLocal DNS Cache? (y/n): " remove_cache
if [[ "$remove_cache" == "y" ]]; then
    kubectl delete daemonset node-local-dns -n kube-system --ignore-not-found=true
    echo -e "${GREEN}✅ NodeLocal DNS Cache removed${NC}"
fi

# Namespace (optional)
echo ""
read -p "Delete monitoring namespace? (This will also remove Prometheus/Grafana) (y/n): " delete_ns
if [[ "$delete_ns" == "y" ]]; then
    echo "Deleting monitoring namespace..."
    kubectl delete namespace monitoring --ignore-not-found=true
    echo -e "${GREEN}✅ Monitoring namespace deleted${NC}"
else
    # Remove just namespace resources
    kubectl delete -f manifests/01-namespace/ --ignore-not-found=true 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
