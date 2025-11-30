#!/bin/bash
set -e

# OAuth2 Sidecar Installation Script
# This script helps you quickly deploy OAuth2 Sidecar to your Kubernetes cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Banner
echo "=========================================="
echo "   OAuth2 Sidecar Installation Wizard"
echo "=========================================="
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    log_warning "helm not found. Will use kubectl apply instead."
    USE_HELM=false
else
    USE_HELM=true
    log_success "helm found"
fi

# Check Kubernetes connection
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please configure kubectl."
    exit 1
fi
log_success "Connected to Kubernetes cluster"

# Check for Istio (support both istio-system and AKS Istio layout)
if kubectl get namespace istio-system &> /dev/null; then
    ISTIO_NS="istio-system"
elif kubectl get namespace aks-istio-system &> /dev/null; then
    ISTIO_NS="aks-istio-system"
else
    log_error "Istio not found. Please install Istio first."
    log_info "Visit: https://istio.io/latest/docs/setup/getting-started/"
    exit 1
fi
log_success "Istio detected in namespace '$ISTIO_NS'"

echo ""
log_info "Starting configuration wizard..."
echo ""

# Configuration prompts
read -p "Enter your domain (e.g., example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    log_error "Domain is required"
    exit 1
fi

read -p "Enter cookie domain (default: .$DOMAIN): " COOKIE_DOMAIN
COOKIE_DOMAIN=${COOKIE_DOMAIN:-".$DOMAIN"}

echo ""
log_info "Select OAuth provider:"
echo "  1) GitHub"
echo "  2) Google"
echo "  3) Azure AD"
echo "  4) Generic OIDC"
read -p "Enter choice [1-4]: " PROVIDER_CHOICE

case $PROVIDER_CHOICE in
    1)
        PROVIDER="github"
        log_info "Selected: GitHub"
        log_info "Register OAuth App: https://github.com/settings/developers"
        ;;
    2)
        PROVIDER="google"
        log_info "Selected: Google"
        log_info "Create OAuth Client: https://console.cloud.google.com/apis/credentials"
        ;;
    3)
        PROVIDER="azure"
        log_info "Selected: Azure AD"
        log_info "Register App: https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps"
        ;;
    4)
        PROVIDER="oidc"
        log_info "Selected: Generic OIDC"
        read -p "Enter OIDC Issuer URL: " OIDC_ISSUER
        ;;
    *)
        log_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
log_info "Enter OAuth application credentials:"
read -p "Client ID: " CLIENT_ID
read -sp "Client Secret: " CLIENT_SECRET
echo ""

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    log_error "Client ID and Secret are required"
    exit 1
fi

# Generate cookie secret
log_info "Generating cookie secret..."
COOKIE_SECRET=$(openssl rand -base64 32)
log_success "Cookie secret generated"

# Provider-specific configuration
PROVIDER_CONFIG=""
case $PROVIDER in
    github)
        read -p "Restrict to GitHub organization (optional): " GITHUB_ORG
        if [ -n "$GITHUB_ORG" ]; then
            PROVIDER_CONFIG="$PROVIDER_CONFIG --set oauth.github.org=$GITHUB_ORG"
        fi
        ;;
    google)
        read -p "Restrict to Google Workspace domain (optional): " GOOGLE_DOMAIN
        if [ -n "$GOOGLE_DOMAIN" ]; then
            PROVIDER_CONFIG="$PROVIDER_CONFIG --set oauth.google.hostedDomain=$GOOGLE_DOMAIN"
        fi
        ;;
    azure)
        read -p "Azure AD Tenant ID: " AZURE_TENANT
        if [ -n "$AZURE_TENANT" ]; then
            PROVIDER_CONFIG="$PROVIDER_CONFIG --set oauth.azure.tenant=$AZURE_TENANT"
        fi
        ;;
    oidc)
        if [ -n "$OIDC_ISSUER" ]; then
            PROVIDER_CONFIG="$PROVIDER_CONFIG --set oauth.oidc.issuerURL=$OIDC_ISSUER"
        fi
        ;;
esac

# Check for TLS secret
echo ""
log_info "Checking for TLS certificate..."
read -p "Enter TLS secret name (or press Enter to skip): " TLS_SECRET

if [ -n "$TLS_SECRET" ]; then
    if kubectl get secret -n "$ISTIO_NS" "$TLS_SECRET" &> /dev/null; then
        log_success "TLS secret '$TLS_SECRET' found in namespace '$ISTIO_NS'"
        TLS_CONFIG="--set istio.gateway.tls.credentialName=$TLS_SECRET"
    else
        log_warning "TLS secret '$TLS_SECRET' not found in namespace '$ISTIO_NS'"
        read -p "Continue without TLS? (y/N): " CONTINUE
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
            exit 1
        fi
        TLS_CONFIG=""
    fi
else
    log_warning "No TLS secret specified. You'll need to configure TLS manually."
    TLS_CONFIG=""
fi

# Installation method
echo ""
if [ "$USE_HELM" = true ]; then
    log_info "Installing via Helm..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Helm chart
    helm upgrade --install oauth2-sidecar ./helm/oauth2-sidecar \
        --namespace default \
        --set domain="$DOMAIN" \
        --set cookieDomain="$COOKIE_DOMAIN" \
        --set oauth.provider="$PROVIDER" \
        --set oauth.clientID="$CLIENT_ID" \
        --set oauth.clientSecret="$CLIENT_SECRET" \
        --set oauth.cookieSecret="$COOKIE_SECRET" \
        $PROVIDER_CONFIG \
        $TLS_CONFIG \
        --wait
    
    log_success "Helm chart installed successfully!"
else
    log_info "Installing via kubectl..."
    
    # Create secret
    kubectl create secret generic oauth2-proxy-secret \
        --namespace=default \
        --from-literal=client-id="$CLIENT_ID" \
        --from-literal=client-secret="$CLIENT_SECRET" \
        --from-literal=cookie-secret="$COOKIE_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply kustomize
    # Note: This assumes kustomize is available
    kubectl apply -k ./k8s/base/
    
    log_success "Resources deployed successfully!"
fi

# Get Istio gateway IP
echo ""
log_info "Retrieving Istio Gateway information from namespace '$ISTIO_NS'..."
GATEWAY_IP=$(kubectl get svc -n "$ISTIO_NS" -l istio=ingressgateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$GATEWAY_IP" ]; then
    log_success "Istio Gateway IP: $GATEWAY_IP"
    echo ""
    log_info "Next steps:"
    echo "  1. Configure DNS: *.$DOMAIN -> $GATEWAY_IP"
    echo "  2. Deploy your application with the OAuth2 sidecar"
    echo "  3. Create a VirtualService routing to your app"
else
    log_warning "Could not retrieve Istio Gateway IP"
    log_info "Run this command to get the IP:"
    echo "    kubectl get svc -n $ISTIO_NS -l istio=ingressgateway"
fi

echo ""
log_info "Configuration Summary:"
echo "  Domain: $DOMAIN"
echo "  Provider: $PROVIDER"
echo "  Cookie Domain: $COOKIE_DOMAIN"
if [ -n "$TLS_SECRET" ]; then
    echo "  TLS Secret: $TLS_SECRET"
fi

echo ""
log_success "✅ OAuth2 Sidecar installation complete!"
echo ""
log_info "For examples and documentation, visit:"
echo "  https://github.com/ianlintner/authproxy"
echo ""
log_info "To add authentication to an app, see:"
echo "  ./examples/simple-app/"
echo ""
