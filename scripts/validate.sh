#!/usr/bin/env bash

set -euo pipefail

# validate.sh - Validate OAuth2 sidecar infrastructure setup
#
# This script checks that the OAuth2 sidecar infrastructure is properly configured

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_NAMESPACE="default"
ISTIO_NAMESPACE="aks-istio-ingress"

ERRORS=0
WARNINGS=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((ERRORS++))
}

check_kubectl() {
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is installed"
    else
        log_error "kubectl not found"
        return 1
    fi
    
    if kubectl cluster-info &> /dev/null; then
        log_success "Connected to Kubernetes cluster"
    else
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
}

check_istio() {
    log_info "Checking Istio installation..."
    
    if kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_success "Istio namespace exists"
    else
        log_error "Istio namespace '$ISTIO_NAMESPACE' not found"
        return 1
    fi
    
    if kubectl get svc -n "$ISTIO_NAMESPACE" aks-istio-ingressgateway-external &> /dev/null; then
        log_success "Istio ingress gateway service exists"
        
        local ip=$(kubectl get svc -n "$ISTIO_NAMESPACE" aks-istio-ingressgateway-external \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$ip" ]; then
            log_success "Ingress gateway has IP: $ip"
        else
            log_warning "Ingress gateway IP not assigned yet"
        fi
    else
        log_error "Istio ingress gateway service not found"
    fi
}

check_oauth2_config() {
    log_info "Checking OAuth2 sidecar configuration..."
    
    if kubectl get configmap oauth2-proxy-sidecar-config -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_success "OAuth2 sidecar ConfigMap exists"
    else
        log_error "OAuth2 sidecar ConfigMap not found in namespace $DEFAULT_NAMESPACE"
    fi
    
    if kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_success "OAuth2 secret exists"
        
        # Check if secret has required keys
        local has_client_id=$(kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" \
            -o jsonpath='{.data.client-id}' 2>/dev/null || echo "")
        local has_client_secret=$(kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" \
            -o jsonpath='{.data.client-secret}' 2>/dev/null || echo "")
        local has_cookie_secret=$(kubectl get secret oauth2-proxy-secret -n "$DEFAULT_NAMESPACE" \
            -o jsonpath='{.data.cookie-secret}' 2>/dev/null || echo "")
        
        if [ -n "$has_client_id" ] && [ -n "$has_client_secret" ] && [ -n "$has_cookie_secret" ]; then
            log_success "OAuth2 secret has all required keys"
        else
            log_error "OAuth2 secret is missing required keys (client-id, client-secret, cookie-secret)"
        fi
    else
        log_error "OAuth2 secret not found in namespace $DEFAULT_NAMESPACE"
    fi
}

check_istio_resources() {
    log_info "Checking Istio resources..."
    
    if kubectl get gateway -n "$ISTIO_NAMESPACE" cat-herding-gateway &> /dev/null; then
        log_success "Istio Gateway exists"
    else
        log_error "Istio Gateway 'cat-herding-gateway' not found"
    fi
    
    # Check TLS certificate
    if kubectl get secret -n "$ISTIO_NAMESPACE" cat-herding-wildcard-tls &> /dev/null; then
        log_success "TLS certificate secret exists"
    else
        log_warning "TLS certificate 'cat-herding-wildcard-tls' not found"
        log_warning "You need to create a wildcard certificate for *.cat-herding.net"
    fi
}

check_example_app() {
    log_info "Checking example app (if deployed)..."
    
    if kubectl get deployment example-app -n "$DEFAULT_NAMESPACE" &> /dev/null; then
        log_success "Example app deployment exists"
        
        # Check if example app has oauth2-proxy sidecar
        local has_sidecar=$(kubectl get deployment example-app -n "$DEFAULT_NAMESPACE" \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="oauth2-proxy")].name}' 2>/dev/null || echo "")
        
        if [ "$has_sidecar" = "oauth2-proxy" ]; then
            log_success "Example app has oauth2-proxy sidecar container"
        else
            log_warning "Example app does not have oauth2-proxy sidecar"
        fi
        
        # Check pod status
        local running_pods=$(kubectl get pods -n "$DEFAULT_NAMESPACE" -l app=example-app \
            --field-selector=status.phase=Running -o name | wc -l)
        
        if [ "$running_pods" -gt 0 ]; then
            log_success "Example app has $running_pods running pod(s)"
        else
            log_warning "Example app has no running pods"
        fi
        
        # Check VirtualService
        if kubectl get virtualservice example-app -n "$DEFAULT_NAMESPACE" &> /dev/null; then
            log_success "Example app VirtualService exists"
        else
            log_warning "Example app VirtualService not found"
        fi
    else
        log_info "Example app not deployed (optional)"
    fi
}

print_summary() {
    echo ""
    echo "======================================"
    echo "         Validation Summary"
    echo "======================================"
    
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        log_success "All checks passed! ✅"
        echo ""
        echo "Your OAuth2 sidecar infrastructure is ready to use."
        echo ""
        echo "Next steps:"
        echo "  1. Deploy an app with OAuth2 sidecar:"
        echo "     kubectl apply -k k8s/apps/example-app/"
        echo ""
        echo "  2. Or add sidecar to existing app:"
        echo "     ./scripts/add-sidecar.sh <app-name> <namespace> <port> <domain>"
        return 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "${YELLOW}Validation completed with $WARNINGS warning(s) ⚠${NC}"
        echo ""
        echo "Your setup is functional but has some warnings."
        echo "Review the warnings above for improvements."
        return 0
    else
        echo -e "${RED}Validation failed with $ERRORS error(s) and $WARNINGS warning(s) ✗${NC}"
        echo ""
        echo "Please fix the errors above before proceeding."
        echo "Run './scripts/setup.sh' to deploy missing components."
        return 1
    fi
}

# Main execution
main() {
    echo ""
    log_info "🔍 Validating OAuth2 Sidecar Infrastructure"
    echo ""
    
    check_kubectl
    check_istio
    check_oauth2_config
    check_istio_resources
    check_example_app
    
    echo ""
    print_summary
}

main "$@"
