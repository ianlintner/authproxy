# Setup Guide

Complete step-by-step guide to deploy the SSO authentication gateway on your AKS cluster.

## Prerequisites

### Required

- ✅ AKS cluster `bigboy` in resource group `nekoc`
- ✅ Istio installed on the cluster
- ✅ cert-manager installed
- ✅ `kubectl` configured with cluster access
- ✅ Domain `cat-herding.net` with DNS access
- ✅ OAuth application registered (GitHub, Google, etc.)

### Tools

- `kubectl` (v1.20+)
- `kustomize` (optional, kubectl has built-in support)
- `openssl` (for generating secrets)
- `curl` (for testing)

## Step 1: Verify Prerequisites

```bash
# Check kubectl connection
kubectl cluster-info

# Check Istio installation
kubectl get namespace istio-system
kubectl get deployment -n istio-system istio-ingressgateway

# Check cert-manager
kubectl get namespace cert-manager
kubectl get pods -n cert-manager

# Get ingress gateway IP
kubectl get svc -n istio-system istio-ingressgateway
```

Note the `EXTERNAL-IP` - this is where your DNS should point.

## Step 2: Configure DNS

Create a wildcard DNS A record for `*.cat-herding.net` pointing to your Istio ingress gateway IP.

**Azure DNS Example**:
```bash
# Get the IP
INGRESS_IP=$(kubectl get svc -n istio-system istio-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Point *.cat-herding.net to: $INGRESS_IP"
```

**Manual DNS Configuration**:
- Record Type: `A`
- Name: `*` (wildcard)
- Value: `<INGRESS_IP>`
- TTL: `300` (or as needed)

**Verify DNS**:
```bash
# Wait for DNS propagation (may take a few minutes)
nslookup auth.cat-herding.net
nslookup example-app.cat-herding.net
```

## Step 3: Create TLS Certificate

If you don't already have a wildcard certificate, create one with cert-manager.

### Option A: Let's Encrypt (HTTP-01 Challenge)

```yaml
# Save as tls-certificate.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Change this!
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: istio

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cat-herding-wildcard
  namespace: istio-system
spec:
  secretName: cat-herding-wildcard-tls
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - "*.cat-herding.net"
  - "cat-herding.net"
```

Apply:
```bash
kubectl apply -f tls-certificate.yaml

# Wait for certificate to be ready
kubectl wait --for=condition=ready certificate/cat-herding-wildcard \
  -n istio-system --timeout=300s

# Verify
kubectl get certificate -n istio-system cat-herding-wildcard
kubectl get secret -n istio-system cat-herding-wildcard-tls
```

### Option B: Bring Your Own Certificate

```bash
# If you have existing cert and key files
kubectl create secret tls cat-herding-wildcard-tls \
  -n istio-system \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem
```

## Step 4: Register OAuth Application

Choose your OAuth provider and register an application.

### GitHub OAuth App

1. Go to: https://github.com/settings/developers
2. Click **"New OAuth App"**
3. Fill in:
   - **Application name**: `Cat Herding SSO`
   - **Homepage URL**: `https://cat-herding.net`
   - **Authorization callback URL**: `https://auth.cat-herding.net/oauth2/callback`
4. Click **"Register application"**
5. Note the **Client ID**
6. Generate a **Client Secret**

### Google OAuth 2.0 Client

1. Go to: https://console.cloud.google.com/apis/credentials
2. Create credentials → OAuth 2.0 Client ID
3. Application type: **Web application**
4. Authorized redirect URIs: `https://auth.cat-herding.net/oauth2/callback`
5. Note the **Client ID** and **Client Secret**

### Azure AD B2C

1. Go to Azure Portal → Azure AD B2C
2. App registrations → New registration
3. Name: `Cat Herding SSO`
4. Redirect URI: `https://auth.cat-herding.net/oauth2/callback`
5. Note **Application (client) ID**
6. Certificates & secrets → New client secret
7. Note the **OIDC Issuer URL** from your B2C tenant

## Step 5: Configure OAuth Secrets

```bash
cd /path/to/authproxy

# Copy the example secret file
cp k8s/base/oauth2-proxy/secret.yaml.example k8s/base/oauth2-proxy/secret.yaml

# Generate a random cookie secret
COOKIE_SECRET=$(openssl rand -base64 32)
echo "Cookie Secret: $COOKIE_SECRET"

# Edit the secret file with your OAuth credentials
nano k8s/base/oauth2-proxy/secret.yaml
```

**For GitHub**:
```yaml
stringData:
  client-id: "your_github_client_id"
  client-secret: "your_github_client_secret"
  cookie-secret: "your_generated_cookie_secret"
```

**For Google**:
```yaml
stringData:
  client-id: "your_google_client_id.apps.googleusercontent.com"
  client-secret: "your_google_client_secret"
  cookie-secret: "your_generated_cookie_secret"
```

Also update the provider in `k8s/base/oauth2-proxy/deployment.yaml`:

```yaml
args:
- --provider=github  # Change to: google, oidc, azure, etc.
```

For OIDC providers (like Azure AD B2C), add:
```yaml
args:
- --provider=oidc
- --oidc-issuer-url=https://your-tenant.b2clogin.com/...
```

## Step 6: Update Kustomization

Edit `k8s/base/kustomization.yaml` to include your secret:

```yaml
resources:
  # ... other resources ...
  - oauth2-proxy/secret.yaml  # Uncomment this line
```

## Step 7: Deploy the Infrastructure

Run the automated setup script:

```bash
./scripts/setup.sh
```

This script will:
1. ✅ Check prerequisites
2. ✅ Create auth namespace
3. ✅ Deploy oauth2-proxy
4. ✅ Configure Istio Gateway and EnvoyFilter
5. ✅ Validate the deployment

**Expected Output**:
```
[INFO] 🚀 Setting up SSO Authentication Gateway for AKS cluster 'bigboy'

[SUCCESS] Prerequisites check passed!
[SUCCESS] OAuth2 secret configuration found!
[INFO] Deploying base authentication infrastructure...
[SUCCESS] oauth2-proxy deployed successfully!
[INFO] Deploying Istio configuration...
[SUCCESS] Istio configuration deployed successfully!
[SUCCESS] TLS certificate 'cat-herding-wildcard-tls' found!
[SUCCESS] Ingress IP: x.x.x.x
[SUCCESS] All validations passed!

✅ Authentication infrastructure deployed successfully!
```

### Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Deploy base infrastructure
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/rbac/
kubectl apply -f k8s/base/oauth2-proxy/

# Deploy Istio configuration
kubectl apply -f k8s/base/istio/

# Verify
kubectl get pods -n auth
kubectl get gateway -n istio-system
kubectl get envoyfilter -n istio-system
```

## Step 8: Deploy Example Application

```bash
# Deploy the example app
kubectl apply -k k8s/apps/example-app/

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app=example-app -n example-app --timeout=60s

# Verify
kubectl get pods -n example-app
kubectl get virtualservice -n example-app
kubectl get authorizationpolicy -n example-app
```

## Step 9: Test Authentication

### Test 1: Check oauth2-proxy Health

```bash
# Internal health check
kubectl exec -n auth deploy/oauth2-proxy -- \
  wget -q -O- http://localhost:4180/ping

# Should output: OK
```

### Test 2: Access Example App

```bash
# Try to access the app
curl -v https://example-app.cat-herding.net

# Expected: 302 redirect to OAuth provider login page
```

### Test 3: Full Flow Test

1. Open browser: https://example-app.cat-herding.net
2. You should be redirected to GitHub/Google/etc. login
3. Log in with your social account
4. You should be redirected back to the app
5. Access any other `*.cat-herding.net` subdomain
6. You should NOT be prompted to log in again (SSO!)

### Test 4: Validate Setup Script

```bash
./scripts/validate.sh example-app.cat-herding.net

# Run full test
./scripts/validate.sh example-app.cat-herding.net full
```

## Step 10: Add Authentication to Your Apps

### Quick Method

Use the helper script:

```bash
./scripts/add-app.sh myapp myapp-namespace 8080
```

This generates VirtualService and AuthorizationPolicy for your app.

### Manual Method

1. **Add label to your Deployment**:

```yaml
metadata:
  labels:
    auth.cat-herding.net/enabled: "true"
```

2. **Create VirtualService**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
  namespace: myapp-namespace
spec:
  hosts:
  - "myapp.cat-herding.net"
  gateways:
  - istio-system/cat-herding-gateway
  http:
  - route:
    - destination:
        host: myapp.myapp-namespace.svc.cluster.local
        port:
          number: 8080
```

3. **Create AuthorizationPolicy**:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: myapp-require-auth
  namespace: myapp-namespace
spec:
  selector:
    matchLabels:
      app: myapp
      auth.cat-herding.net/enabled: "true"
  action: CUSTOM
  provider:
    name: oauth2-proxy
  rules:
  - to:
    - operation:
        paths: ["/*"]
```

4. **Apply**:

```bash
kubectl apply -f myapp-virtualservice.yaml
kubectl apply -f myapp-authorizationpolicy.yaml
```

5. **Test**:

```bash
curl -v https://myapp.cat-herding.net
```

## Monitoring and Maintenance

### View Logs

```bash
# oauth2-proxy logs
kubectl logs -n auth -l app=oauth2-proxy -f

# Filter auth events
kubectl logs -n auth -l app=oauth2-proxy | grep -i "authsuccess\|authfailure"

# Istio ingress gateway logs
kubectl logs -n istio-system -l app=istio-ingressgateway -f
```

### Check Metrics

```bash
# oauth2-proxy metrics
kubectl port-forward -n auth svc/oauth2-proxy 44180:44180
curl http://localhost:44180/metrics

# Look for:
# oauth2_proxy_requests_total
# oauth2_proxy_authentication_total
```

### Update OAuth Credentials

```bash
# Edit the secret
kubectl edit secret -n auth oauth2-proxy-secret

# Or replace the secret file and reapply
kubectl apply -f k8s/base/oauth2-proxy/secret.yaml

# Restart oauth2-proxy to pick up changes
kubectl rollout restart deployment/oauth2-proxy -n auth
```

### Rotate Cookie Secret

```bash
# Generate new secret
NEW_COOKIE_SECRET=$(openssl rand -base64 32)

# Update secret
kubectl patch secret oauth2-proxy-secret -n auth \
  -p "{\"stringData\":{\"cookie-secret\":\"$NEW_COOKIE_SECRET\"}}"

# Restart oauth2-proxy
kubectl rollout restart deployment/oauth2-proxy -n auth
```

**Warning**: This invalidates all existing sessions. Users will need to re-authenticate.

## Troubleshooting

### Issue: oauth2-proxy pods not starting

**Check**:
```bash
kubectl describe pod -n auth -l app=oauth2-proxy
kubectl logs -n auth -l app=oauth2-proxy
```

**Common causes**:
- Invalid OAuth credentials
- Missing secret
- Resource constraints

**Fix**:
```bash
# Verify secret exists
kubectl get secret -n auth oauth2-proxy-secret

# Check secret values
kubectl get secret -n auth oauth2-proxy-secret -o yaml
```

### Issue: 503 Service Unavailable

**Possible causes**:
1. oauth2-proxy is down
2. EnvoyFilter misconfiguration
3. Backend service unavailable

**Check**:
```bash
# Check oauth2-proxy health
kubectl get pods -n auth -l app=oauth2-proxy

# Test auth endpoint directly
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://oauth2-proxy.auth.svc.cluster.local:4180/ping

# Check EnvoyFilter
kubectl get envoyfilter -n istio-system ext-authz -o yaml
```

### Issue: Redirect loop

**Possible causes**:
1. Callback URL mismatch
2. Cookie domain mismatch
3. Invalid OAuth configuration

**Check**:
```bash
# Verify callback URL in OAuth app matches
echo "Should be: https://auth.cat-herding.net/oauth2/callback"

# Check oauth2-proxy config
kubectl get deployment -n auth oauth2-proxy -o yaml | grep -A 5 "args:"

# Check logs for errors
kubectl logs -n auth -l app=oauth2-proxy | grep -i error
```

### Issue: TLS certificate errors

**Check**:
```bash
# Verify certificate exists
kubectl get secret -n istio-system cat-herding-wildcard-tls

# Check certificate status (if using cert-manager)
kubectl get certificate -n istio-system

# View certificate details
kubectl get secret -n istio-system cat-herding-wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

### Issue: DNS not resolving

**Check**:
```bash
# Test DNS
nslookup auth.cat-herding.net
nslookup example-app.cat-herding.net

# Verify ingress IP
kubectl get svc -n istio-system istio-ingressgateway

# Check if LoadBalancer has external IP
```

### Issue: Authentication works but user headers not appearing

**Check**:
```bash
# Verify EnvoyFilter includes headers
kubectl get envoyfilter -n istio-system ext-authz -o yaml

# Look for allowed_upstream_headers section

# Check oauth2-proxy config includes header forwarding
kubectl get deployment -n auth oauth2-proxy -o yaml | \
  grep -i "set-xauthrequest\|pass-user-headers"
```

**Test**:
```bash
# Deploy a debug pod that echoes headers
kubectl run echo --image=ealen/echo-server:latest -n example-app

# Access it through the auth gateway and check headers
```

## Uninstall

To remove the authentication infrastructure:

```bash
# Remove example app
kubectl delete -k k8s/apps/example-app/

# Remove Istio configuration
kubectl delete -f k8s/base/istio/

# Remove oauth2-proxy
kubectl delete -f k8s/base/oauth2-proxy/
kubectl delete -f k8s/base/rbac/

# Remove namespace
kubectl delete -f k8s/base/namespace.yaml

# Optional: Remove TLS certificate
kubectl delete certificate -n istio-system cat-herding-wildcard
kubectl delete secret -n istio-system cat-herding-wildcard-tls
```

## Next Steps

- Read [ADDING_APPS.md](ADDING_APPS.md) for app integration guide
- Review [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture
- Set up monitoring and alerting
- Configure additional OAuth providers
- Implement centralized logging

## Support

For issues or questions:
1. Check [ARCHITECTURE.md](ARCHITECTURE.md) for design details
2. Review [ADDING_APPS.md](ADDING_APPS.md) for app integration
3. Check oauth2-proxy logs: `kubectl logs -n auth -l app=oauth2-proxy`
4. Verify Istio config: `kubectl get envoyfilter,gateway,virtualservice -n istio-system`

## References

- [OAuth2 Proxy Configuration](https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview)
- [Istio External Authorization](https://istio.io/latest/docs/tasks/security/authorization/authz-custom/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)
