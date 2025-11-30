#!/usr/bin/env bash

set -euo pipefail

# setup.sh - Deploy OAuth2 proxy sidecar infrastructure
#
# This script sets up the base infrastructure needed for OAuth2 authentication
# using the sidecar pattern. Each application will have its own oauth2-proxy container.
#
# What this deploys:
#   - OAuth2 proxy secret (for OAuth credentials)
#   - OAuth2 proxy sidecar ConfigMap (base configuration)
#   - Istio Gateway for *.cat-herding.net
#
# What this does NOT deploy:
#   - Individual applications (use example in k8s/apps/example-app-sidecar/)
#   - Centralized oauth2-proxy (removed in favor of sidecar pattern)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="bigboy"
RESOURCE_GROUP="nekoc"
DEFAULT_NAMESPACE="default"
ISTIO_NAMESPACE="aks-istio-ingress"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check if connected to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please configure kubectl."
        exit 1
    fi
    
    # Check if Istio is installed
    if ! kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_error "Istio namespace '$ISTIO_NAMESPACE' not found. Please install Istio first."
        exit 1
    fi
    
    # Check if AKS Istio external ingress gateway exists
    if ! kubectl get svc -n "$ISTIO_NAMESPACE" aks-istio-ingressgateway-external &> /dev/null; then
        log_error "AKS Istio external ingress gateway service not found."
        log_error "Expected service: aks-istio-ingressgateway-external in namespace $ISTIO_NAMESPACE"
        exit 1
    fi
    
    log_success "Prerequisites check passed!"
}

check_secret() {
    log_info "Checking for OAuth2 secret configuration..."
    
    # Check if secret file exists
    if [ ! -f "k8s/base/oauth2-proxy-sidecar/secret.yaml" ]; then
        log_error "OAuth2 secret file not found!"
        echo
        echo "Please create k8s/base/oauth2-proxy-sidecar/secret.yaml with your OAuth credentials."
        echo
        echo "Steps:"
        echo "  1. Copy the example: cp k8s/base/oauth2-proxy-sidecar/secret.yaml.example k8s/base/oauth2-proxy-sidecar/secret.yaml"
        echo "  2. Edit the file with your OAuth client ID and secret"
        echo "  3. Generate cookie secret: python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'"
        echo "  4. Run this script again"
        echo
        exit 1
    fi
    
    # Check if secret already exists in cluster
    if kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_warning "Secret oauth2-proxy-secret already exists in namespace $DEFAULT_NAMESPACE"
        read -p "Do you want to update it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping secret update"
            return
        fi
    fi
    
    log_info "Applying OAuth2 secret..."
    kubectl apply -f k8s/base/oauth2-proxy-sidecar/secret.yaml
    log_success "OAuth2 secret configured!"
}

deploy_base_infrastructure() {
    log_info "Deploying base OAuth2 sidecar infrastructure..."
    
    # Deploy OAuth2 proxy sidecar ConfigMap
    log_info "Deploying oauth2-proxy sidecar ConfigMap..."
    kubectl apply -f k8s/base/oauth2-proxy-sidecar/configmap-sidecar.yaml
    
    log_success "OAuth2 sidecar infrastructure deployed successfully!"
}

deploy_istio_configuration() {
    log_info "Deploying Istio configuration..."
    
    # Deploy Gateway
    log_info "Creating Istio Gateway for *.cat-herding.net..."
    kubectl apply -f k8s/base/istio/gateway.yaml
    
    log_success "Istio Gateway deployed successfully!"
}

check_tls_certificate() {
    log_info "Checking for TLS certificate..."
    
    if kubectl get secret -n "$ISTIO_NAMESPACE" cat-herding-wildcard-tls &> /dev/null; then
        log_success "TLS certificate 'cat-herding-wildcard-tls' found!"
    else
        log_warning "TLS certificate 'cat-herding-wildcard-tls' not found in $ISTIO_NAMESPACE"
        log_warning "You need to create a wildcard certificate for *.cat-herding.net"
        log_warning ""
        log_warning "Example with cert-manager:"
        log_warning "  kubectl apply -f - <<EOF"
        log_warning "  apiVersion: cert-manager.io/v1"
        log_warning "  kind: Certificate"
        log_warning "  metadata:"
        log_warning "    name: cat-herding-wildcard"
        log_warning "    namespace: $ISTIO_NAMESPACE"
        log_warning "  spec:"
        log_warning "    secretName: cat-herding-wildcard-tls"
        log_warning "    issuerRef:"
        log_warning "      name: letsencrypt-prod"
        log_warning "      kind: ClusterIssuer"
        log_warning "    dnsNames:"
        log_warning "    - '*.cat-herding.net'"
        log_warning "    - 'cat-herding.net'"
        log_warning "  EOF"
    fi
}

get_ingress_ip() {
    log_info "Getting Istio ingress gateway IP..."
    
    local max_attempts=30
    local attempt=1
    local ip=""
    
    while [ $attempt -le $max_attempts ]; do
        ip=$(kubectl get svc -n "$ISTIO_NAMESPACE" aks-istio-ingressgateway-external \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$ip" ]; then
            log_success "Ingress IP: $ip"
            log_info "Make sure your DNS *.cat-herding.net points to this IP"
            return 0
        fi
        
        log_info "Waiting for LoadBalancer IP... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_warning "Could not get LoadBalancer IP. Check manually:"
    log_warning "  kubectl get svc -n $ISTIO_NAMESPACE aks-istio-ingressgateway-external"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check ConfigMap
    if kubectl get configmap oauth2-proxy-sidecar-config -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_success "OAuth2 sidecar ConfigMap is configured"
    else
        log_error "OAuth2 sidecar ConfigMap not found!"
        exit 1
    fi
    
    # Check Secret
    if kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_success "OAuth2 secret is configured"
    else
        log_error "OAuth2 secret not found!"
        exit 1
    fi
    
    # Check Gateway
    if kubectl get gateway -n "$ISTIO_NAMESPACE" cat-herding-gateway &> /dev/null; then
        log_success "Gateway 'cat-herding-gateway' is configured"
    else
        log_error "Gateway 'cat-herding-gateway' not found!"
        exit 1
    fi
    
    log_success "All validations passed!"
}

print_next_steps() {
    echo ""
    log_success "✅ OAuth2 Sidecar Infrastructure deployed successfully!"
    echo ""
    log_info "Next steps:"
    echo ""
    echo "  1. Verify TLS certificate is ready:"
    echo "     kubectl get certificate -n $ISTIO_NAMESPACE"
    echo ""
    echo "  2. Deploy the example app with OAuth2 sidecar:"
    echo "     kubectl apply -k k8s/apps/example-app-sidecar/"
    echo ""
    echo "  3. Test authentication flow:"
    echo "     curl -v https://example-app.cat-herding.net"
    echo ""
    echo "  4. Add OAuth2 sidecar to existing app:"
    echo "     ./scripts/add-sidecar.sh <app-name> <namespace> <app-port> <domain>"
    echo ""
    echo "     Example:"
    echo "     ./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net"
    echo ""
    echo "  5. View app logs (including oauth2-proxy sidecar):"
    echo "     kubectl logs -n <namespace> <pod-name> -c oauth2-proxy"
    echo ""
    log_info "📚 Documentation:"
    echo "     - README.md - Overview and quick start"
    echo "     - docs/ARCHITECTURE.md - Detailed architecture"
    echo "     - docs/ADDING_APPS.md - Guide for adding auth to apps"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "🚀 Setting up OAuth2 Sidecar Infrastructure for AKS cluster '$CLUSTER_NAME'"
    echo ""
    
    
    check_prerequisites
    check_secret
    deploy_base_infrastructure
    deploy_istio_configuration
    check_tls_certificate
    get_ingress_ip
    validate_deployment
    print_next_steps
}

# Main execution
main() {
    echo ""
    log_info "🚀 Setting up OAuth2 Sidecar Infrastructure for AKS cluster '$CLUSTER_NAME'"
    echo ""
    
    check_prerequisites
    check_secret
    deploy_base_infrastructure
    deploy_istio_configuration
    check_tls_certificate
    get_ingress_ip
    validate_deployment
    print_next_steps
}

main "$@"
