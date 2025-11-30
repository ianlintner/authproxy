# Adding OAuth2 Authentication to Your Applications

This guide walks you through adding OAuth2 authentication to new or existing applications using the sidecar pattern.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: Deploy New App with Authentication](#method-1-deploy-new-app-with-authentication)
- [Method 2: Add Authentication to Existing App](#method-2-add-authentication-to-existing-app)
- [Testing Your Setup](#testing-your-setup)
- [Customization Options](#customization-options)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Before adding authentication to your app, ensure:

1. **Base infrastructure is deployed**:
   ```bash
   ./scripts/setup.sh
   ```

2. **OAuth secret exists**:
   ```bash
   kubectl get secret oauth2-proxy-secret -n default
   ```

3. **DNS is configured**: `*.cat-herding.net` points to Istio ingress gateway

4. **TLS certificate is ready**:
   ```bash
   kubectl get secret cat-herding-wildcard-tls -n aks-istio-ingress
   ```

## Method 1: Deploy New App with Authentication

Use the complete example in `k8s/apps/example-app/` as your starting point.

Key points:
- oauth2-proxy sidecar listens on port 4180
- Your app container listens on port 8080 (configurable)
- Service exposes port 4180
- VirtualService routes to port 4180

See `k8s/apps/example-app/README.md` for detailed instructions.

## Method 2: Add Authentication to Existing App

### Automated (Recommended)

```bash
./scripts/add-sidecar.sh <app-name> <namespace> <app-port> <domain>

# Example:
./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
```

This script automatically:
- ✅ Adds oauth2-proxy sidecar to deployment
- ✅ Updates service to expose port 4180
- ✅ Creates/updates VirtualService
- ✅ Deploys changes

### Manual

See the complete manual steps in the full guide.

## Testing Your Setup

```bash
# 1. Check pods running
kubectl get pods -l app=myapp

# 2. Test authentication
curl -v https://myapp.cat-herding.net
# Should redirect to OAuth provider (302)

# 3. Test in browser
# - Visit https://myapp.cat-herding.net
# - Should redirect to GitHub/Google
# - Log in
# - Should redirect back to app

# 4. Test SSO
# - Log in to app1.cat-herding.net
# - Visit app2.cat-herding.net
# - Should be automatically logged in
```

## Customization Options

### Different App Port

```yaml
env:
- name: OAUTH2_PROXY_UPSTREAMS
  value: "http://127.0.0.1:3000"  # Your app port
```

### Restrict Email Domain

```yaml
env:
- name: OAUTH2_PROXY_EMAIL_DOMAINS
  value: "mycompany.com"
```

### Different OAuth Provider

Update ConfigMap:
```
provider = "google"
# OR
provider = "azure"
```

## Troubleshooting

### 503 Service Unavailable

```bash
# Check pods
kubectl get pods -l app=myapp

# Check logs
kubectl logs <pod-name> -c oauth2-proxy
kubectl logs <pod-name> -c app
```

### Redirect Loop

Check redirect URL matches domain:
```bash
kubectl get deployment myapp -o yaml | grep REDIRECT_URL
```

Should be: `https://myapp.cat-herding.net/oauth2/callback`

### User Headers Not Available

Verify in ConfigMap:
```
pass_user_headers = true
set_xauthrequest = true
```

Your app should read:
- `X-Auth-Request-User`
- `X-Auth-Request-Email`

## Next Steps

- Review [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design
- See example: `k8s/apps/example-app/`
- Run validation: `./scripts/validate.sh`
