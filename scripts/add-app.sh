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

# Check arguments
if [ $# -ne 3 ]; then
    log_error "Usage: $0 <app-name> <namespace> <port>"
    log_error ""
    log_error "Examples:"
    log_error "  $0 chat chat-app 3000"
    log_error "  $0 dashboard dashboard-ns 8080"
    log_error "  $0 api api-service 5000"
    exit 1
fi

APP_NAME="$1"
NAMESPACE="$2"
PORT="$3"
HOSTNAME="${APP_NAME}.cat-herding.net"
OUTPUT_DIR="k8s/apps/${APP_NAME}"
ISTIO_NAMESPACE="istio-system"

log_info "Generating authentication manifests for app: $APP_NAME"
log_info "Namespace: $NAMESPACE"
log_info "Port: $PORT"
log_info "Hostname: $HOSTNAME"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate VirtualService
log_info "Creating VirtualService..."
cat > "$OUTPUT_DIR/virtualservice.yaml" <<EOF
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    auth.cat-herding.net/enabled: "true"
spec:
  hosts:
  - "${HOSTNAME}"
  gateways:
  - ${ISTIO_NAMESPACE}/cat-herding-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: ${APP_NAME}.${NAMESPACE}.svc.cluster.local
        port:
          number: ${PORT}
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
      retryOn: gateway-error,connect-failure,refused-stream
EOF

# Generate AuthorizationPolicy
log_info "Creating AuthorizationPolicy..."
cat > "$OUTPUT_DIR/authorization-policy.yaml" <<EOF
---
# AuthorizationPolicy that enforces authentication via ext_authz
# This policy requires successful authentication from oauth2-proxy
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ${APP_NAME}-require-auth
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    auth.cat-herding.net/enabled: "true"
spec:
  # Apply to pods with the auth label
  selector:
    matchLabels:
      app: ${APP_NAME}
      auth.cat-herding.net/enabled: "true"
  
  # CUSTOM action defers to ext_authz (oauth2-proxy)
  action: CUSTOM
  
  provider:
    name: oauth2-proxy
  
  rules:
  # Apply to all requests
  - to:
    - operation:
        paths: ["/*"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

---
# Optional: Allow health check endpoints without authentication
# Uncomment if your app has health check endpoints
# apiVersion: security.istio.io/v1
# kind: AuthorizationPolicy
# metadata:
#   name: ${APP_NAME}-allow-healthcheck
#   namespace: ${NAMESPACE}
# spec:
#   selector:
#     matchLabels:
#       app: ${APP_NAME}
#   action: ALLOW
#   rules:
#   - to:
#     - operation:
#         paths: ["/health", "/healthz", "/ready", "/readyz", "/livez"]
EOF

# Generate kustomization.yaml
log_info "Creating kustomization.yaml..."
cat > "$OUTPUT_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

resources:
  - virtualservice.yaml
  - authorization-policy.yaml

commonLabels:
  app.kubernetes.io/name: ${APP_NAME}
  app.kubernetes.io/managed-by: kustomize
  app.kubernetes.io/part-of: cat-herding-apps
  auth.cat-herding.net/enabled: "true"
EOF

# Generate README
log_info "Creating README..."
cat > "$OUTPUT_DIR/README.md" <<EOF
# ${APP_NAME} - Authentication Configuration

This directory contains Istio configuration to enable OAuth2 authentication for **${APP_NAME}**.

## Overview

- **Application**: ${APP_NAME}
- **Namespace**: ${NAMESPACE}
- **Hostname**: ${HOSTNAME}
- **Port**: ${PORT}

## What This Does

1. Routes requests from \`${HOSTNAME}\` to your application
2. Enforces authentication via oauth2-proxy
3. Injects user identity headers into requests

## Deployment

\`\`\`bash
# Apply the configuration
kubectl apply -k k8s/apps/${APP_NAME}/

# Verify
kubectl get virtualservice -n ${NAMESPACE} ${APP_NAME}
kubectl get authorizationpolicy -n ${NAMESPACE} ${APP_NAME}-require-auth
\`\`\`

## Add Auth Label to Your Deployment

Make sure your application Deployment has the authentication label:

\`\`\`yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    auth.cat-herding.net/enabled: "true"  # Add this label
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        auth.cat-herding.net/enabled: "true"  # Add this label to pods too
    spec:
      containers:
      - name: app
        image: your-image:tag
        ports:
        - containerPort: ${PORT}
\`\`\`

## Access User Identity

Your application will receive these headers:

- \`X-Auth-Request-User\`: Username
- \`X-Auth-Request-Email\`: User email
- \`X-Auth-Request-Preferred-Username\`: Preferred username
- \`Authorization\`: Bearer token (if configured)

### Example Code

**Node.js/Express:**
\`\`\`javascript
app.get('/', (req, res) => {
  const email = req.headers['x-auth-request-email'];
  const user = req.headers['x-auth-request-user'];
  console.log(\`User: \${user} (\${email})\`);
});
\`\`\`

**Python/Flask:**
\`\`\`python
@app.route('/')
def index():
    email = request.headers.get('X-Auth-Request-Email')
    user = request.headers.get('X-Auth-Request-User')
    print(f"User: {user} ({email})")
\`\`\`

## Testing

\`\`\`bash
# Test the authentication flow
curl -v https://${HOSTNAME}

# You should be redirected to the OAuth login page
# After login, you'll be redirected back to the app
\`\`\`

## Troubleshooting

### Check VirtualService
\`\`\`bash
kubectl get virtualservice -n ${NAMESPACE} ${APP_NAME} -o yaml
\`\`\`

### Check AuthorizationPolicy
\`\`\`bash
kubectl get authorizationpolicy -n ${NAMESPACE} ${APP_NAME}-require-auth -o yaml
\`\`\`

### View oauth2-proxy logs
\`\`\`bash
kubectl logs -n auth -l app=oauth2-proxy -f
\`\`\`

### Test without auth (for debugging)
Temporarily delete the AuthorizationPolicy:
\`\`\`bash
kubectl delete authorizationpolicy -n ${NAMESPACE} ${APP_NAME}-require-auth
\`\`\`

Re-apply when done debugging.

## Disable Authentication

To disable authentication:

\`\`\`bash
# Delete the auth configuration
kubectl delete -k k8s/apps/${APP_NAME}/

# Or just remove the AuthorizationPolicy
kubectl delete authorizationpolicy -n ${NAMESPACE} ${APP_NAME}-require-auth

# And remove the label from your Deployment
kubectl label deployment -n ${NAMESPACE} ${APP_NAME} auth.cat-herding.net/enabled-
\`\`\`
EOF

log_success "✅ Authentication manifests generated!"
echo ""
log_info "Files created in: $OUTPUT_DIR"
echo "  - virtualservice.yaml"
echo "  - authorization-policy.yaml"
echo "  - kustomization.yaml"
echo "  - README.md"
echo ""
log_info "Next steps:"
echo ""
echo "  1. Make sure your Deployment has the auth label:"
echo "     auth.cat-herding.net/enabled: \"true\""
echo ""
echo "  2. Apply the configuration:"
echo "     kubectl apply -k $OUTPUT_DIR/"
echo ""
echo "  3. Test the authentication:"
echo "     curl -v https://$HOSTNAME"
echo ""
log_info "📚 See $OUTPUT_DIR/README.md for detailed instructions"
echo ""
