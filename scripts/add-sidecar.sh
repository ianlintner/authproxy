#!/bin/bash
set -euo pipefail

# add-sidecar.sh - Add OAuth2 proxy sidecar to an existing deployment
#
# Usage:
#   ./scripts/add-sidecar.sh <app-name> <namespace> <app-port> <domain>
#
# Example:
#   ./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
#
# This script will:
#   1. Validate the deployment exists
#   2. Add the oauth2-proxy sidecar container
#   3. Update the service to expose port 4180
#   4. Create/update VirtualService to route to port 4180
#   5. Deploy the updated configuration

APP_NAME="${1:-}"
NAMESPACE="${2:-default}"
APP_PORT="${3:-8080}"
DOMAIN="${4:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}WARN: $1${NC}"
}

# Validate inputs
if [[ -z "$APP_NAME" ]]; then
    error "App name is required. Usage: $0 <app-name> <namespace> <app-port> <domain>"
fi

if [[ -z "$DOMAIN" ]]; then
    DOMAIN="${APP_NAME}.cat-herding.net"
    info "No domain specified, using: $DOMAIN"
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please install kubectl."
fi

# Check if deployment exists
if ! kubectl get deployment "$APP_NAME" -n "$NAMESPACE" &> /dev/null; then
    error "Deployment $APP_NAME not found in namespace $NAMESPACE"
fi

info "Adding OAuth2 proxy sidecar to $APP_NAME in namespace $NAMESPACE"

# Create temporary directory for patching
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Create sidecar container patch
cat > "$TEMP_DIR/sidecar-patch.yaml" <<EOF
spec:
  template:
    metadata:
      annotations:
        auth.cat-herding.net/provider: "oauth2-proxy-sidecar"
        auth.cat-herding.net/domain: "$DOMAIN"
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: proxy
          containerPort: 4180
          protocol: TCP
        env:
        - name: OAUTH2_PROXY_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-id
        - name: OAUTH2_PROXY_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-secret
        - name: OAUTH2_PROXY_COOKIE_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: cookie-secret
        - name: OAUTH2_PROXY_REDIRECT_URL
          value: "https://$DOMAIN/oauth2/callback"
        - name: OAUTH2_PROXY_UPSTREAMS
          value: "http://127.0.0.1:$APP_PORT"
        volumeMounts:
        - name: oauth2-proxy-config
          mountPath: /etc/oauth2-proxy
          readOnly: true
        args:
        - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 2000
          capabilities:
            drop:
            - ALL
      volumes:
      - name: oauth2-proxy-config
        configMap:
          name: oauth2-proxy-sidecar-config
EOF

# Apply the patch
info "Patching deployment $APP_NAME..."
kubectl patch deployment "$APP_NAME" -n "$NAMESPACE" --patch-file "$TEMP_DIR/sidecar-patch.yaml" --type strategic

# Update or create service
if kubectl get service "$APP_NAME" -n "$NAMESPACE" &> /dev/null; then
    info "Updating service $APP_NAME to expose port 4180..."
    kubectl patch service "$APP_NAME" -n "$NAMESPACE" --type json -p '[
        {
            "op": "add",
            "path": "/spec/ports/-",
            "value": {
                "name": "proxy",
                "port": 4180,
                "targetPort": 4180,
                "protocol": "TCP"
            }
        }
    ]' 2>/dev/null || warn "Port 4180 may already exist on service"
else
    info "Creating service $APP_NAME..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  type: ClusterIP
  ports:
  - name: proxy
    port: 4180
    targetPort: 4180
    protocol: TCP
  selector:
    app: $APP_NAME
EOF
fi

# Create or update VirtualService
info "Creating/updating VirtualService for $DOMAIN..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  hosts:
  - "$DOMAIN"
  gateways:
  - istio-system/main-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: $APP_NAME.$NAMESPACE.svc.cluster.local
        port:
          number: 4180
EOF

info "✅ OAuth2 proxy sidecar added successfully!"
echo
echo "Next steps:"
echo "1. Ensure oauth2-proxy-secret exists in namespace $NAMESPACE"
echo "   kubectl get secret oauth2-proxy-secret -n $NAMESPACE"
echo
echo "2. Ensure oauth2-proxy-sidecar-config ConfigMap exists"
echo "   kubectl get configmap oauth2-proxy-sidecar-config -n $NAMESPACE"
echo
echo "3. Wait for deployment to rollout"
echo "   kubectl rollout status deployment/$APP_NAME -n $NAMESPACE"
echo
echo "4. Test your application at https://$DOMAIN"
echo
info "All traffic will now require OAuth authentication!"
