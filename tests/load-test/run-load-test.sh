#!/bin/bash
set -euo pipefail

echo "========================================="
echo "DNS Load Test"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "This will create 10 pods making continuous DNS queries."
echo "Use this to test DNS throttling detection and auto-remediation."
echo ""

echo -e "${YELLOW}⚠️  WARNING: This generates significant DNS load!${NC}"
echo "Only run this in test/staging environments."
echo ""

read -p "Start load test? (y/n): " start

if [[ "$start" != "y" ]]; then
    echo "Load test cancelled."
    exit 0
fi

# Deploy load test
echo ""
echo "Deploying DNS load test pods..."
kubectl apply -f "$(dirname "$0")/dns-load-deployment.yaml"

echo ""
echo -e "${GREEN}✅ Load test deployed!${NC}"
echo ""
echo "Monitor the following:"
echo ""
echo -e "${YELLOW}1. DNS Metrics in Prometheus:${NC}"
echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "   Query: kubernetes_dns_linklocal_allowance_exceeded"
echo ""
echo -e "${YELLOW}2. CoreDNS Scaling:${NC}"
echo "   watch kubectl get deployment coredns -n kube-system"
echo ""
echo -e "${YELLOW}3. Grafana Dashboard:${NC}"
echo "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "   Open: http://localhost:3000"
echo ""
echo -e "${YELLOW}4. Alert Status:${NC}"
echo "   kubectl port-forward -n monitoring svc/alertmanager-prometheus-kube-prometheus-alertmanager 9093:9093"
echo "   Open: http://localhost:9093"
echo ""
echo -e "${YELLOW}5. Load Test Logs:${NC}"
echo "   kubectl logs -f deployment/dns-load-test"
echo ""
echo -e "${RED}To stop the load test:${NC}"
echo "   kubectl delete deployment dns-load-test"
echo ""

# Wait a moment for pods to start
sleep 5

# Show current status
echo "Current status:"
kubectl get pods -l app=dns-load-test

echo ""
echo "Monitoring for 30 seconds..."
sleep 30

# Check if throttling occurred
echo ""
echo "Checking if DNS throttling was triggered..."
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

if kill -0 $PF_PID 2>/dev/null; then
    THROTTLE=$(curl -s "http://localhost:9090/api/v1/query?query=kubernetes_dns_linklocal_allowance_exceeded" 2>/dev/null | grep -o '"value":\[[^]]*\]' || echo "")
    kill $PF_PID 2>/dev/null
    wait $PF_PID 2>/dev/null || true
    
    if [[ -n "$THROTTLE" ]] && [[ "$THROTTLE" != *',"0"'* ]]; then
        echo -e "${YELLOW}⚠️  DNS throttling detected!${NC}"
        echo "Check auto-remediation: kubectl get deployment coredns -n kube-system"
    else
        echo -e "${GREEN}No throttling detected yet. Continue monitoring.${NC}"
    fi
else
    echo "Could not check throttling status (Prometheus not accessible)"
fi

echo ""
echo "Load test is running. Remember to clean up when done:"
echo "  kubectl delete deployment dns-load-test"
echo ""
