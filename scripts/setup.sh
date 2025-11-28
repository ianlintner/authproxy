#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="bigboy"
RESOURCE_GROUP="nekoc"
AUTH_NAMESPACE="default"
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
    
    # Check kustomize
    if ! command -v kustomize &> /dev/null; then
        log_warning "kustomize not found. Will use kubectl apply -k instead."
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
    
    # Check if AKS Istio external ingress gateway service exists
    if ! kubectl get svc -n "$ISTIO_NAMESPACE" aks-istio-ingressgateway-external &> /dev/null; then
        log_error "AKS Istio external ingress gateway service not found."
        log_error "Expected service: aks-istio-ingressgateway-external in namespace $ISTIO_NAMESPACE"
        exit 1
    fi
    
    # Check if cert-manager is installed
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_warning "cert-manager namespace not found. Make sure cert-manager is installed for TLS."
    fi
    
    log_success "Prerequisites check passed!"
}

check_secret() {
    log_info "Checking for OAuth2 secret configuration..."
    
    local has_file_secret=0
    local has_spc=0
    local has_existing_secret=0

    if [ -f "k8s/base/oauth2-proxy/secret.yaml" ]; then
        has_file_secret=1
    fi

    if kubectl get secretproviderclass -n "$AUTH_NAMESPACE" spc-oauth2-proxy &> /dev/null; then
        has_spc=1
    elif [ -f "k8s/base/azure/secretproviderclass-oauth2-proxy.yaml" ]; then
        # Apply SPC manifest if present locally
        log_info "Applying SecretProviderClass for Azure Key Vault (spc-oauth2-proxy)..."
        kubectl apply -f k8s/base/azure/secretproviderclass-oauth2-proxy.yaml
        has_spc=1
    fi

    if kubectl get secret -n "$AUTH_NAMESPACE" oauth2-proxy-secret &> /dev/null; then
        has_existing_secret=1
    fi

    if [ $has_file_secret -eq 1 ] || [ $has_spc -eq 1 ] || [ $has_existing_secret -eq 1 ]; then
        log_success "OAuth2 secret configuration detected (file or Azure Key Vault or existing secret)."
    else
        log_error "OAuth2 secret not configured!"
        log_error "Provide one of the following before continuing:"
        log_error "  A) Create k8s/base/oauth2-proxy/secret.yaml from secret.yaml.example and fill values"
        log_error "  B) Configure Azure Key Vault via k8s/base/azure/secretproviderclass-oauth2-proxy.yaml (preferred)"
        log_error "  C) Create an existing secret named 'oauth2-proxy-secret' in namespace '$AUTH_NAMESPACE'"
        log_error ""
        log_error "GitHub OAuth App guidance: https://github.com/settings/developers"
        log_error "Callback URL: https://auth.cat-herding.net/oauth2/callback"
        exit 1
    fi
}

deploy_base_infrastructure() {
    log_info "Deploying base authentication infrastructure..."
    
    # Note: Using default namespace - no need to create it
    log_info "Deploying to default namespace..."    
    # kubectl apply -f k8s/base/namespace.yaml  # Not needed for default namespace
    
    # Deploy RBAC
    log_info "Deploying RBAC..."
    kubectl apply -f k8s/base/rbac/
    
    # Deploy oauth2-proxy secret (file-based) if present
    if [ -f "k8s/base/oauth2-proxy/secret.yaml" ]; then
        log_info "Deploying oauth2-proxy secret (file-based)..."
        kubectl apply -f k8s/base/oauth2-proxy/secret.yaml
    fi
    
    # Deploy oauth2-proxy
    log_info "Deploying oauth2-proxy..."
    # Apply Azure Key Vault SecretProviderClass if present
    if [ -f "k8s/base/azure/secretproviderclass-oauth2-proxy.yaml" ]; then
        kubectl apply -f k8s/base/azure/secretproviderclass-oauth2-proxy.yaml || true
    fi
    kubectl apply -f k8s/base/oauth2-proxy/configmap.yaml
    kubectl apply -f k8s/base/oauth2-proxy/deployment.yaml
    kubectl apply -f k8s/base/oauth2-proxy/service.yaml
    
    # Wait for oauth2-proxy to be ready
    log_info "Waiting for oauth2-proxy to be ready..."
    kubectl wait --for=condition=available --timeout=120s \
        deployment/oauth2-proxy -n "$AUTH_NAMESPACE" || {
        log_error "oauth2-proxy failed to become ready"
        log_info "Check logs: kubectl logs -n $AUTH_NAMESPACE -l app=oauth2-proxy"
        exit 1
    }
    
    log_success "oauth2-proxy deployed successfully!"
}

deploy_istio_configuration() {
    log_info "Deploying Istio configuration..."
    
    # Deploy Gateway
    log_info "Creating Istio Gateway for *.cat-herding.net..."
    kubectl apply -f k8s/base/istio/gateway.yaml
    
    # Deploy VirtualService for auth
    log_info "Creating VirtualService for auth.cat-herding.net..."
    kubectl apply -f k8s/base/istio/virtualservice-auth.yaml
    
    # Deploy EnvoyFilter for ext_authz
    log_info "Creating EnvoyFilter for external authorization..."
    kubectl apply -f k8s/base/istio/ext-authz-filter.yaml
    
    # Wait a moment for Envoy config to propagate
    log_info "Waiting for Envoy configuration to propagate (10s)..."
    sleep 10
    
    log_success "Istio configuration deployed successfully!"
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
    
    # Check oauth2-proxy pods
    local pod_count=$(kubectl get pods -n "$AUTH_NAMESPACE" -l app=oauth2-proxy \
        --field-selector=status.phase=Running -o name | wc -l)
    
    if [ "$pod_count" -gt 0 ]; then
        log_success "oauth2-proxy has $pod_count running pod(s)"
    else
        log_error "No running oauth2-proxy pods found!"
        exit 1
    fi
    
    # Check EnvoyFilter
    if kubectl get envoyfilter -n "$ISTIO_NAMESPACE" ext-authz &> /dev/null; then
        log_success "EnvoyFilter 'ext-authz' is configured"
    else
        log_error "EnvoyFilter 'ext-authz' not found!"
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
    log_success "✅ Authentication infrastructure deployed successfully!"
    echo ""
    log_info "Next steps:"
    echo ""
    echo "  1. Verify TLS certificate is ready:"
    echo "     kubectl get certificate -n $ISTIO_NAMESPACE"
    echo ""
    echo "  2. Test oauth2-proxy health:"
    echo "     kubectl exec -n $AUTH_NAMESPACE deploy/oauth2-proxy -- wget -O- http://localhost:4180/ping"
    echo ""
    echo "  3. Deploy the example app:"
    echo "     kubectl apply -k k8s/apps/example-app/"
    echo ""
    echo "  4. Test authentication flow:"
    echo "     curl -v https://example-app.cat-herding.net"
    echo ""
    echo "  5. Add auth to your own app:"
    echo "     ./scripts/add-app.sh <app-name> <namespace> <port>"
    echo ""
    echo "  6. View oauth2-proxy logs:"
    echo "     kubectl logs -n $AUTH_NAMESPACE -l app=oauth2-proxy -f"
    echo ""
    log_info "📚 Documentation: docs/SETUP.md"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "🚀 Setting up SSO Authentication Gateway for AKS cluster '$CLUSTER_NAME'"
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

# Run main function
main "$@"
