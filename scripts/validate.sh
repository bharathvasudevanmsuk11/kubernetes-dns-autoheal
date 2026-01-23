#!/bin/bash
set -euo pipefail

echo "========================================="
echo "DNS Throttling Solution - Validation"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILURES=0

# Check function
check() {
    local name="$1"
    local command="$2"
    
    echo -n "Checking $name... "
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL${NC}"
        ((FAILURES++))
    fi
}

# Namespace
check "Monitoring namespace" "kubectl get namespace monitoring"

# DaemonSet
check "DNS Monitor DaemonSet" "kubectl get daemonset dns-throttle-monitor -n monitoring"
check "DNS Monitor pods running" "kubectl get pods -n monitoring -l app=dns-throttle-monitor -o jsonpath='{.items[0].status.phase}' | grep -q Running"

# Count DaemonSet pods
EXPECTED_PODS=$(kubectl get nodes --no-headers | wc -l)
ACTUAL_PODS=$(kubectl get pods -n monitoring -l app=dns-throttle-monitor --no-headers 2>/dev/null | wc -l)
echo -n "Checking DaemonSet coverage ($ACTUAL_PODS/$EXPECTED_PODS nodes)... "
if [[ $ACTUAL_PODS -eq $EXPECTED_PODS ]]; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: Expected $EXPECTED_PODS pods, found $ACTUAL_PODS${NC}"
fi

# Prometheus
check "Prometheus installed" "kubectl get prometheus -n monitoring"
check "Prometheus pod running" "kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' | grep -q Running"

# ServiceMonitor
check "ServiceMonitor created" "kubectl get servicemonitor dns-throttle-monitor -n monitoring"

# PrometheusRule
check "PrometheusRule created" "kubectl get prometheusrule dns-throttling-alerts -n monitoring"

# Auto-scaler
check "CoreDNS autoscaler" "kubectl get deployment dns-autoscaler -n kube-system"

# Remediation webhook
check "Remediation webhook deployment" "kubectl get deployment remediation-webhook -n monitoring"
check "Remediation webhook pods" "kubectl get pods -n monitoring -l app=remediation-webhook -o jsonpath='{.items[0].status.phase}' | grep -q Running"

# Metrics collection
echo ""
echo "Checking metrics collection..."
if command -v timeout &> /dev/null; then
    TIMEOUT_CMD="timeout 5"
else
    TIMEOUT_CMD=""
fi

kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

if kill -0 $PF_PID 2>/dev/null; then
    METRICS=$($TIMEOUT_CMD curl -s "http://localhost:9090/api/v1/query?query=up{job='dns-throttle-monitor'}" 2>/dev/null | grep -o '"result":\[.*\]' || echo "")
    kill $PF_PID 2>/dev/null
    wait $PF_PID 2>/dev/null || true
    
    if [[ -n "$METRICS" ]] && [[ "$METRICS" != *'"result":[]'* ]]; then
        echo -e "${GREEN}✅ Metrics are being collected${NC}"
    else
        echo -e "${YELLOW}⚠️  No metrics found yet (may take a few minutes)${NC}"
        echo "   Run: kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=20"
    fi
else
    echo -e "${YELLOW}⚠️  Could not check metrics (Prometheus not accessible)${NC}"
fi

echo ""
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo "========================================="
    exit 0
else
    echo -e "${RED}❌ $FAILURES check(s) failed${NC}"
    echo "========================================="
    echo ""
    echo "Troubleshooting tips:"
    echo "1. Check pod logs: kubectl logs -n monitoring -l app=dns-throttle-monitor"
    echo "2. Describe pods: kubectl describe pod -n monitoring -l app=dns-throttle-monitor"
    echo "3. Check events: kubectl get events -n monitoring --sort-by='.lastTimestamp'"
    echo ""
    exit 1
fi
