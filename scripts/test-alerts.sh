#!/bin/bash
set -euo pipefail

echo "========================================="
echo "Testing Alert Routing"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Port forward to Alertmanager
echo "Setting up port forward to Alertmanager..."
kubectl port-forward -n monitoring svc/alertmanager-prometheus-kube-prometheus-alertmanager 9093:9093 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

if ! kill -0 $PF_PID 2>/dev/null; then
    echo "❌ Failed to port-forward to Alertmanager"
    exit 1
fi

# Test alert payload
ALERT_PAYLOAD='{
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "DNSThrottlingWarning",
        "severity": "warning",
        "team": "sre",
        "instance": "test-node-1"
      },
      "annotations": {
        "summary": "Test DNS throttling alert",
        "description": "This is a test alert to verify routing"
      },
      "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }
  ]
}'

# Send test alert
echo "Sending test alert to Alertmanager..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "$ALERT_PAYLOAD" \
  http://localhost:9093/api/v2/alerts)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

# Cleanup
kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null || true

echo ""
if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✅ Test alert sent successfully!${NC}"
else
    echo "❌ Failed to send alert (HTTP $HTTP_CODE)"
    exit 1
fi

echo ""
echo "Check the following:"
echo "  1. Slack channel for notification"
echo "  2. Email inbox for SRE team"
echo "  3. Remediation webhook logs:"
echo "     kubectl logs -n monitoring -l app=remediation-webhook --tail=20"
echo ""
echo "  4. Alertmanager UI:"
echo "     kubectl port-forward -n monitoring svc/alertmanager-prometheus-kube-prometheus-alertmanager 9093:9093"
echo "     Open: http://localhost:9093"
echo ""
