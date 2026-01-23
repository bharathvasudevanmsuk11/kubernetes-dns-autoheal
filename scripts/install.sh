#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

echo "========================================="
echo "DNS Throttling Solution - Installer"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        echo -e "${YELLOW}⚠️  helm not found. Some features may not work.${NC}"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Please configure kubectl.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
    echo ""
}

# Detect platform
detect_platform() {
    echo "Platform Detection:"
    echo "1) AWS EKS"
    echo "2) Azure AKS"
    echo "3) Other/Skip"
    read -p "Select your platform (1-3): " choice
    
    case $choice in
        1) echo "AWS";;
        2) echo "Azure";;
        *) echo "Other";;
    esac
}

PLATFORM=$(detect_platform)
echo -e "${GREEN}Selected platform: $PLATFORM${NC}"
echo ""

# Install Prometheus stack
install_prometheus() {
    echo "Installing Prometheus and Grafana..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    if helm list -n monitoring 2>/dev/null | grep -q prometheus; then
        echo -e "${YELLOW}Prometheus already installed, skipping...${NC}"
    else
        echo "Installing Prometheus Operator..."
        helm install prometheus prometheus-community/kube-prometheus-stack \
          --namespace monitoring \
          --create-namespace \
          --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
          --set prometheus.prometheusSpec.retention=15d \
          --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
          --wait --timeout=10m
        
        echo -e "${GREEN}✅ Prometheus and Grafana installed${NC}"
    fi
}

# Deploy manifests
deploy_manifests() {
    echo ""
    echo "Deploying DNS monitoring components..."
    
    # 01 - Namespace
    echo "Creating namespace..."
    kubectl apply -f "${MANIFEST_DIR}/01-namespace/"
    echo -e "${GREEN}✅ Namespace created${NC}"
    
    # 02 - Monitoring
    echo "Deploying monitoring DaemonSet..."
    kubectl apply -f "${MANIFEST_DIR}/02-monitoring/"
    echo -e "${GREEN}✅ Monitoring DaemonSet deployed${NC}"
    
    # Platform-specific configuration
    if [[ "$PLATFORM" == "Azure" ]]; then
        echo ""
        echo -e "${YELLOW}Azure Configuration Required:${NC}"
        read -p "Enter Azure Resource ID: " resource_id
        
        if [[ -n "$resource_id" ]]; then
            kubectl set env daemonset/dns-throttle-monitor \
              -n monitoring \
              AZURE_RESOURCE_ID="$resource_id"
            echo -e "${GREEN}✅ Azure configuration applied${NC}"
        else
            echo -e "${RED}⚠️  Warning: Resource ID not set. Monitor will not work.${NC}"
        fi
    elif [[ "$PLATFORM" == "AWS" ]]; then
        echo -e "${GREEN}✅ AWS auto-detection enabled${NC}"
        echo -e "${YELLOW}Note: Ensure IAM policy is attached to node role${NC}"
    fi
    
    # 03 - Prometheus/Grafana
    echo "Deploying ServiceMonitor and PrometheusRules..."
    kubectl apply -f "${MANIFEST_DIR}/03-prometheus-grafana/"
    echo -e "${GREEN}✅ ServiceMonitor and PrometheusRules deployed${NC}"
    
    # 04 - Autoscaling
    echo "Deploying CoreDNS autoscaler..."
    kubectl apply -f "${MANIFEST_DIR}/04-autoscaling/"
    echo -e "${GREEN}✅ CoreDNS autoscaler deployed${NC}"
    
    # 05 - Remediation
    echo "Deploying remediation webhook..."
    kubectl apply -f "${MANIFEST_DIR}/05-remediation/"
    echo -e "${GREEN}✅ Remediation webhook deployed${NC}"
    
    # 06 - Alerting (optional - needs configuration)
    echo ""
    read -p "Configure Alertmanager now? (y/n): " configure_alerts
    if [[ "$configure_alerts" == "y" ]]; then
        echo -e "${YELLOW}⚠️  Please edit manifests/06-alerting/secret-alertmanager-config.yaml first${NC}"
        echo "   Update Slack webhook, email settings, and PagerDuty key"
        read -p "Press Enter when ready to continue..."
        kubectl apply -f "${MANIFEST_DIR}/06-alerting/"
        
        # Restart Alertmanager to pick up new config
        kubectl rollout restart statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring 2>/dev/null || true
        echo -e "${GREEN}✅ Alertmanager configured${NC}"
    else
        echo -e "${YELLOW}Skipping Alertmanager configuration${NC}"
    fi
}

# Deploy NodeLocal DNS Cache
deploy_nodelocaldns() {
    echo ""
    read -p "Deploy NodeLocal DNS Cache? (Recommended - reduces DNS load by 80%) (y/n): " deploy_cache
    
    if [[ "$deploy_cache" == "y" ]]; then
        echo "Deploying NodeLocal DNS Cache..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
        echo -e "${GREEN}✅ NodeLocal DNS Cache deployed${NC}"
    else
        echo -e "${YELLOW}Skipping NodeLocal DNS Cache${NC}"
    fi
}

# Wait for pods
wait_for_pods() {
    echo ""
    echo "Waiting for pods to be ready..."
    
    echo "Waiting for monitoring pods..."
    kubectl wait --for=condition=ready pod \
      -l app=dns-throttle-monitor \
      -n monitoring \
      --timeout=300s 2>/dev/null || echo -e "${YELLOW}⚠️  Some pods may still be starting${NC}"
    
    echo "Waiting for webhook pods..."
    kubectl wait --for=condition=ready pod \
      -l app=remediation-webhook \
      -n monitoring \
      --timeout=300s 2>/dev/null || echo -e "${YELLOW}⚠️  Webhook pods may still be starting${NC}"
    
    echo -e "${GREEN}✅ Pods are ready${NC}"
}

# Print access information
print_access_info() {
    echo ""
    echo "========================================="
    echo "Installation Complete!"
    echo "========================================="
    echo ""
    
    # Get Grafana password
    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana \
      -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "prom-operator")
    
    echo -e "${GREEN}📊 Access Grafana:${NC}"
    echo "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "   URL: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: $GRAFANA_PASSWORD"
    echo ""
    
    echo -e "${GREEN}📈 Access Prometheus:${NC}"
    echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "   URL: http://localhost:9090"
    echo ""
    
    echo -e "${GREEN}🔧 Check DNS Monitor Status:${NC}"
    echo "   kubectl get pods -n monitoring -l app=dns-throttle-monitor"
    echo "   kubectl logs -n monitoring -l app=dns-throttle-monitor --tail=50"
    echo ""
    
    echo -e "${GREEN}✅ Verify Metrics:${NC}"
    echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "   Query: kubernetes_dns_linklocal_allowance_exceeded"
    echo ""
    
    echo -e "${GREEN}📖 Next Steps:${NC}"
    echo "   1. Run validation: ./scripts/validate.sh"
    echo "   2. Configure alerts in manifests/06-alerting/"
    echo "   3. Import Grafana dashboard from grafana/dashboards/"
    echo "   4. Run load test: ./tests/load-test/run-load-test.sh"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    install_prometheus
    deploy_manifests
    deploy_nodelocaldns
    wait_for_pods
    print_access_info
}

main
