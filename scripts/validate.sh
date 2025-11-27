#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <hostname> [test-type]"
    log_error ""
    log_error "Examples:"
    log_error "  $0 example-app.cat-herding.net"
    log_error "  $0 chat.cat-herding.net full"
    log_error ""
    log_error "Test types:"
    log_error "  quick - Basic connectivity test (default)"
    log_error "  full  - Full authentication flow test"
    exit 1
fi

HOSTNAME="$1"
TEST_TYPE="${2:-quick}"
AUTH_NAMESPACE="auth"

log_info "🔍 Validating authentication setup for: $HOSTNAME"
echo ""

# Test 1: Check DNS resolution
test_dns() {
    log_info "Test 1: DNS Resolution"
    
    if host "$HOSTNAME" > /dev/null 2>&1; then
        local ip=$(host "$HOSTNAME" | grep "has address" | awk '{print $4}' | head -1)
        log_success "✓ DNS resolves to: $ip"
    else
        log_error "✗ DNS resolution failed for $HOSTNAME"
        log_warning "Make sure *.cat-herding.net points to your Istio ingress gateway IP"
        return 1
    fi
}

# Test 2: Check oauth2-proxy is running
test_oauth2_proxy() {
    log_info "Test 2: oauth2-proxy Health"
    
    local pod_count=$(kubectl get pods -n "$AUTH_NAMESPACE" -l app=oauth2-proxy \
        --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    
    if [ "$pod_count" -gt 0 ]; then
        log_success "✓ oauth2-proxy has $pod_count running pod(s)"
        
        # Test internal health endpoint
        if kubectl exec -n "$AUTH_NAMESPACE" deploy/oauth2-proxy -- \
            wget -q -O- http://localhost:4180/ping > /dev/null 2>&1; then
            log_success "✓ oauth2-proxy /ping endpoint responding"
        else
            log_warning "⚠ oauth2-proxy /ping endpoint not responding"
        fi
    else
        log_error "✗ No running oauth2-proxy pods found"
        log_error "Run: kubectl get pods -n $AUTH_NAMESPACE"
        return 1
    fi
}

# Test 3: Check Istio configuration
test_istio_config() {
    log_info "Test 3: Istio Configuration"
    
    # Check Gateway
    if kubectl get gateway -n istio-system cat-herding-gateway > /dev/null 2>&1; then
        log_success "✓ Gateway 'cat-herding-gateway' exists"
    else
        log_error "✗ Gateway 'cat-herding-gateway' not found"
        return 1
    fi
    
    # Check EnvoyFilter
    if kubectl get envoyfilter -n istio-system ext-authz > /dev/null 2>&1; then
        log_success "✓ EnvoyFilter 'ext-authz' exists"
    else
        log_error "✗ EnvoyFilter 'ext-authz' not found"
        return 1
    fi
    
    # Check VirtualService for auth
    if kubectl get virtualservice -n "$AUTH_NAMESPACE" oauth2-proxy-virtualservice > /dev/null 2>&1; then
        log_success "✓ VirtualService for auth.cat-herding.net exists"
    else
        log_warning "⚠ VirtualService for oauth2-proxy not found"
    fi
}

# Test 4: Check TLS certificate
test_tls_certificate() {
    log_info "Test 4: TLS Certificate"
    
    if kubectl get secret -n istio-system cat-herding-wildcard-tls > /dev/null 2>&1; then
        log_success "✓ TLS certificate 'cat-herding-wildcard-tls' exists"
        
        # Check if certificate is valid
        local not_after=$(kubectl get secret -n istio-system cat-herding-wildcard-tls \
            -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | \
            openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$not_after" ]; then
            log_success "✓ Certificate expires: $not_after"
        fi
    else
        log_warning "⚠ TLS certificate not found - HTTPS may not work"
    fi
}

# Test 5: Quick HTTP test
test_http_connectivity() {
    log_info "Test 5: HTTP Connectivity"
    
    local url="https://$HOSTNAME"
    
    log_info "Testing: $url"
    
    # Test with curl
    local response=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "$url" 2>/dev/null || echo "000")
    
    case "$response" in
        200)
            log_success "✓ Got 200 OK - Application is accessible"
            ;;
        302|307)
            log_success "✓ Got $response redirect - Authentication flow active"
            log_info "This is expected - you'll be redirected to login"
            ;;
        401)
            log_success "✓ Got 401 Unauthorized - Authentication required"
            log_info "This is expected - authentication is enforced"
            ;;
        403)
            log_warning "⚠ Got 403 Forbidden - Check authorization policies"
            ;;
        404)
            log_error "✗ Got 404 Not Found - Check VirtualService configuration"
            return 1
            ;;
        503)
            log_error "✗ Got 503 Service Unavailable"
            log_error "Possible issues:"
            log_error "  - oauth2-proxy is not running"
            log_error "  - Backend service is not available"
            log_error "  - EnvoyFilter misconfiguration"
            return 1
            ;;
        000)
            log_error "✗ Connection failed - Cannot reach $HOSTNAME"
            log_error "Check DNS and network connectivity"
            return 1
            ;;
        *)
            log_warning "⚠ Got unexpected response: $response"
            ;;
    esac
}

# Test 6: Full authentication flow (optional)
test_full_auth_flow() {
    log_info "Test 6: Full Authentication Flow"
    
    local url="https://$HOSTNAME"
    
    log_info "Testing redirect to OAuth provider..."
    
    # Follow redirects and capture final URL
    local final_url=$(curl -s -L -w "%{url_effective}" -o /dev/null "$url" 2>/dev/null || echo "")
    
    if [[ "$final_url" == *"github.com"* ]] || \
       [[ "$final_url" == *"google.com"* ]] || \
       [[ "$final_url" == *"microsoft.com"* ]] || \
       [[ "$final_url" == *"linkedin.com"* ]] || \
       [[ "$final_url" == *"b2clogin.com"* ]]; then
        log_success "✓ Redirects to OAuth provider: $final_url"
    elif [[ "$final_url" == *"$HOSTNAME"* ]]; then
        log_info "✓ Stays on application (may already be authenticated)"
    else
        log_warning "⚠ Unexpected redirect: $final_url"
    fi
}

# Test 7: Check app-specific configuration
test_app_config() {
    local app_name="${HOSTNAME%%.*}"
    
    log_info "Test 7: Application Configuration"
    
    # Try to find the app's namespace
    local namespaces=$(kubectl get virtualservice --all-namespaces -o json 2>/dev/null | \
        jq -r ".items[] | select(.spec.hosts[] | contains(\"$HOSTNAME\")) | .metadata.namespace" 2>/dev/null || echo "")
    
    if [ -n "$namespaces" ]; then
        for ns in $namespaces; do
            log_success "✓ VirtualService found in namespace: $ns"
            
            # Check if there's an AuthorizationPolicy
            local auth_policies=$(kubectl get authorizationpolicy -n "$ns" -o name 2>/dev/null | wc -l)
            if [ "$auth_policies" -gt 0 ]; then
                log_success "✓ Found $auth_policies AuthorizationPolicy(ies) in $ns"
            else
                log_warning "⚠ No AuthorizationPolicy found in $ns"
                log_warning "Authentication may not be enforced for this app"
            fi
        done
    else
        log_warning "⚠ No VirtualService found for $HOSTNAME"
        log_warning "You may need to create one with: ./scripts/add-app.sh"
    fi
}

# Test 8: Check logs for errors
test_logs() {
    log_info "Test 8: Recent Logs Check"
    
    local error_count=$(kubectl logs -n "$AUTH_NAMESPACE" -l app=oauth2-proxy --tail=50 2>/dev/null | \
        grep -i "error\|failed\|fatal" | wc -l || echo "0")
    
    if [ "$error_count" -eq 0 ]; then
        log_success "✓ No recent errors in oauth2-proxy logs"
    else
        log_warning "⚠ Found $error_count error(s) in recent logs"
        log_info "View logs: kubectl logs -n $AUTH_NAMESPACE -l app=oauth2-proxy"
    fi
}

# Main execution
main() {
    local failed_tests=0
    
    echo ""
    
    # Run tests
    test_oauth2_proxy || ((failed_tests++))
    echo ""
    
    test_istio_config || ((failed_tests++))
    echo ""
    
    test_tls_certificate
    echo ""
    
    test_dns || ((failed_tests++))
    echo ""
    
    test_http_connectivity || ((failed_tests++))
    echo ""
    
    if [ "$TEST_TYPE" == "full" ]; then
        test_full_auth_flow
        echo ""
    fi
    
    test_app_config
    echo ""
    
    test_logs
    echo ""
    
    # Summary
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$failed_tests" -eq 0 ]; then
        log_success "✅ All tests passed!"
        log_info "Your authentication setup appears to be working correctly."
        echo ""
        log_info "Try accessing: https://$HOSTNAME"
        log_info "You should be redirected to login if not authenticated."
    else
        log_error "❌ $failed_tests test(s) failed"
        log_error "Review the errors above and fix the issues."
        echo ""
        log_info "Common fixes:"
        log_info "  - Run ./scripts/setup.sh to deploy infrastructure"
        log_info "  - Check oauth2-proxy logs: kubectl logs -n auth -l app=oauth2-proxy"
        log_info "  - Verify DNS points to ingress IP: kubectl get svc -n istio-system istio-ingressgateway"
        log_info "  - Check TLS cert: kubectl get certificate -n istio-system"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    return $failed_tests
}

# Run main function
main "$@"
