# Architecture: OAuth2 Sidecar Authentication

## Overview

This architecture implements OAuth2 authentication for AKS applications using a **sidecar pattern**. Each application pod includes an `oauth2-proxy` container that handles authentication before requests reach the application container.

**Key Characteristics:**
- **Decentralized**: No shared authentication service
- **Simple**: No complex Istio ext_authz configuration
- **Isolated**: Each app manages its own authentication
- **Portable**: Easy to migrate between clusters

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                        Internet / Users                            │
└──────────────────────────────┬─────────────────────────────────────┘
                               │
                               │ HTTPS (*.cat-herding.net)
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                    Azure Load Balancer                             │
│                    (AKS Public IP)                                 │
└──────────────────────────────┬─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                  Istio Ingress Gateway                             │
│                  (aks-istio-ingressgateway-external)               │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  Gateway: *.cat-herding.net                              │    │
│  │  - TLS Termination (wildcard cert)                       │    │
│  │  - HTTP → HTTPS redirect                                 │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  No ext_authz filter - auth handled by sidecars                   │
└──────────────────────────────┬────────────────────────────────────┘
                               │
                               │ Routes to Service (port 4180)
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                       Application Service                          │
│                       (ClusterIP, port 4180)                       │
└──────────────────────────────┬─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                       Application Pod                              │
│                                                                    │
│  ┌──────────────────────────────────────────────────────┐        │
│  │  oauth2-proxy sidecar container                      │        │
│  │  (port 4180)                                         │        │
│  │                                                      │        │
│  │  1. Receives all traffic                            │        │
│  │  2. Checks session cookie                           │        │
│  │  3. If not auth → redirect to OAuth                 │        │
│  │  4. If auth → proxy to localhost:8080               │        │
│  │  5. Inject user headers                             │        │
│  └───────────────┬──────────────────────────────────────┘        │
│                  │                                                │
│                  │ http://127.0.0.1:8080                         │
│                  │                                                │
│  ┌───────────────▼──────────────────────────────────────┐        │
│  │  Application container                               │        │
│  │  (port 8080)                                         │        │
│  │                                                      │        │
│  │  - Receives authenticated requests                   │        │
│  │  - Reads user from headers                          │        │
│  │  - No auth logic needed                             │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                    │
│  Shared volumes:                                                  │
│  - oauth2-proxy-config (ConfigMap)                                │
│  - oauth2-proxy-secret (Secret)                                   │
└────────────────────────────────────────────────────────────────────┘

                               │
                               │ OAuth flow (if not authenticated)
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│  Social OAuth Provider                                             │
│  - GitHub                                                          │
│  - Google                                                          │
│  - Azure AD                                                        │
│  - LinkedIn                                                        │
│                                                                    │
│  User logs in → callback to app → cookie set                      │
└────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Istio Ingress Gateway

**Purpose**: Entry point for all external HTTPS traffic

**Configuration**:
- **Gateway Resource**: Defines `*.cat-herding.net` hosts
- **TLS**: Uses wildcard certificate `cat-herding-wildcard-tls`
- **Ports**: 80 (HTTP → HTTPS redirect), 443 (HTTPS)

**Key Features**:
- Wildcard DNS support
- Automatic TLS termination
- Routes to application services (port 4180)

**No ext_authz filter**: Unlike centralized auth, the gateway simply routes traffic without authentication checks.

### 2. oauth2-proxy Sidecar Container

**Purpose**: Handle OAuth2 authentication within each application pod

**Configuration** (`k8s/base/oauth2-proxy-sidecar/`):
- **Image**: `quay.io/oauth2-proxy/oauth2-proxy:v7.6.0`
- **Port**: 4180 (receives all traffic)
- **Upstream**: `http://127.0.0.1:8080` (application container)
- **Config**: Mounted from ConfigMap
- **Secrets**: OAuth credentials from Secret

**Environment Variables** (per-app):
```yaml
- name: OAUTH2_PROXY_REDIRECT_URL
  value: "https://myapp.cat-herding.net/oauth2/callback"
- name: OAUTH2_PROXY_UPSTREAMS  
  value: "http://127.0.0.1:8080"
```

**How It Works**:
1. Receives request on port 4180
2. Checks for valid session cookie (`.cat-herding.net` domain)
3. **If not authenticated**:
   - Redirects to OAuth provider
   - Provider redirects back to `/oauth2/callback`
   - Sets encrypted session cookie
   - Redirects to original URL
4. **If authenticated**:
   - Proxies request to `localhost:8080` (app container)
   - Injects user headers

**Headers Injected**:
- `X-Auth-Request-User` - Username
- `X-Auth-Request-Email` - Email address
- `X-Auth-Request-Preferred-Username` - Preferred username
- `Authorization` - Bearer token (if configured)

### 3. Application Container

**Purpose**: Your application code

**Requirements**:
- Listen on port 8080 (or configure via `OAUTH2_PROXY_UPSTREAMS`)
- Read user identity from request headers
- No authentication logic needed

**Example** (Go):
```go
email := r.Header.Get("X-Auth-Request-Email")
user := r.Header.Get("X-Auth-Request-User")
```

### 4. Service

**Purpose**: Expose the oauth2-proxy sidecar (port 4180) to Istio

**Configuration**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  ports:
  - name: proxy
    port: 4180
    targetPort: 4180
  selector:
    app: myapp
```

**Key Point**: Service routes to port 4180 (oauth2-proxy), not directly to app

### 5. VirtualService

**Purpose**: Route traffic from hostname to Service

**Configuration**:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
  - "myapp.cat-herding.net"
  gateways:
  - istio-system/main-gateway
  http:
  - route:
    - destination:
        host: myapp.default.svc.cluster.local
        port:
          number: 4180
```

## Traffic Flow

### First-Time Access (Not Authenticated)

```
1. User visits https://myapp.cat-herding.net
   ↓
2. Istio Gateway (TLS termination)
   ↓
3. VirtualService routes to Service:4180
   ↓
4. Service routes to Pod oauth2-proxy:4180
   ↓
5. oauth2-proxy checks cookie → NOT FOUND
   ↓
6. oauth2-proxy returns 302 redirect to GitHub
   ↓
7. User logs in at GitHub
   ↓
8. GitHub redirects to /oauth2/callback
   ↓
9. oauth2-proxy exchanges code for token
   ↓
10. oauth2-proxy sets encrypted cookie (.cat-herding.net)
   ↓
11. oauth2-proxy returns 302 redirect to original URL
   ↓
12. User's browser re-requests with cookie
```

### Subsequent Access (Authenticated)

```
1. User visits https://myapp.cat-herding.net
   (Cookie: _oauth2_proxy=encrypted_session)
   ↓
2. Istio Gateway (TLS termination)
   ↓
3. VirtualService routes to Service:4180
   ↓
4. Service routes to Pod oauth2-proxy:4180
   ↓
5. oauth2-proxy checks cookie → VALID
   ↓
6. oauth2-proxy proxies to localhost:8080
   (Injects headers: X-Auth-Request-Email, X-Auth-Request-User)
   ↓
7. Application container receives request
   ↓
8. Application reads user from headers
   ↓
9. Application returns response
   ↓
10. oauth2-proxy proxies response back to user
```

## Single Sign-On (SSO)

**How SSO Works Across Apps:**

1. User logs in at `app1.cat-herding.net`
2. Cookie set with domain `.cat-herding.net`
3. User visits `app2.cat-herding.net`
4. Browser automatically sends `.cat-herding.net` cookie
5. app2's oauth2-proxy sidecar validates cookie
6. User is authenticated without re-login!

**Requirements for SSO:**
- All apps use same cookie domain (`.cat-herding.net`)
- All apps use same OAuth provider and client credentials
- All apps deploy oauth2-proxy with identical secret

## Comparison: Sidecar vs Centralized

| Aspect | Sidecar Pattern (New) | Centralized ext_authz (Old) |
|--------|----------------------|----------------------------|
| **Complexity** | Low - simple pod config | High - Istio ext_authz filter |
| **Debugging** | Easy - logs in same pod | Hard - separate service |
| **Isolation** | High - per-app config | Low - shared config |
| **Performance** | Fast - localhost proxy | Slower - network call |
| **Portability** | Easy - self-contained | Hard - Istio specific |
| **Scaling** | Auto - scales with app | Manual - separate deployment |
| **Failure Impact** | Per-app only | All apps affected |

## Security Considerations

### 1. Cookie Security

- **Domain**: `.cat-herding.net` (enables SSO)
- **Secure**: true (HTTPS only)
- **HttpOnly**: true (prevents JavaScript access)
- **SameSite**: lax (balance security/usability)
- **Encryption**: AES-256 with cookie secret

### 2. Secret Management

**Required Secrets**:
- `client-id`: OAuth application ID
- `client-secret`: OAuth application secret
- `cookie-secret`: 32-byte random string for cookie encryption

**Best Practices**:
- Never commit secrets to git
- Use Kubernetes Secrets or Azure Key Vault
- Rotate cookie secret periodically
- Use different OAuth apps per environment (dev/staging/prod)

### 3. Network Security

- All traffic encrypted with TLS
- oauth2-proxy to app communication on localhost only
- No external access to app port (8080)
- Only oauth2-proxy port (4180) exposed via Service

## Configuration Options

### Per-App Customization

Each app can customize via environment variables:

```yaml
env:
- name: OAUTH2_PROXY_REDIRECT_URL
  value: "https://myapp.cat-herding.net/oauth2/callback"
- name: OAUTH2_PROXY_UPSTREAMS
  value: "http://127.0.0.1:8080"
- name: OAUTH2_PROXY_EMAIL_DOMAINS
  value: "mycompany.com"  # Restrict to specific domain
```

### Different OAuth Providers

Update ConfigMap to change provider:

```
provider = "google"
# OR
provider = "azure"
azure_tenant = "your-tenant-id"
# OR
provider = "oidc"
oidc_issuer_url = "https://your-issuer"
```

### Custom Session Duration

```
cookie_expire = "24h"    # Session expires after 24 hours
cookie_refresh = "15m"   # Refresh token every 15 minutes
```

## Monitoring and Observability

### Logs

View oauth2-proxy sidecar logs:
```bash
kubectl logs -n <namespace> <pod-name> -c oauth2-proxy
```

View application logs:
```bash
kubectl logs -n <namespace> <pod-name> -c app
```

### Metrics

oauth2-proxy exposes Prometheus metrics (if configured):
- Request counts
- Authentication success/failure rates
- Session duration
- OAuth provider latency

### Health Checks

oauth2-proxy health endpoint:
```bash
curl http://localhost:4180/ping
```

## Deployment Patterns

### Pattern 1: New Application

1. Write your application (no auth logic)
2. Create Deployment with oauth2-proxy sidecar
3. Create Service exposing port 4180
4. Create VirtualService routing to Service:4180
5. Deploy with `kubectl apply`

See: `k8s/apps/example-app/`

### Pattern 2: Existing Application

1. Use helper script:
   ```bash
   ./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
   ```

2. Script automatically:
   - Patches Deployment with sidecar
   - Updates Service
   - Creates/updates VirtualService

### Pattern 3: Kustomize

Use Kustomize patches to add sidecar to multiple apps:

```yaml
patchesStrategicMerge:
- oauth2-sidecar-patch.yaml
```

## Troubleshooting

### Issue: Redirect Loop

**Symptom**: Browser keeps redirecting between app and OAuth provider

**Causes**:
- `OAUTH2_PROXY_REDIRECT_URL` doesn't match actual domain
- Cookie domain incorrect
- HTTPS not properly configured

**Fix**:
```bash
# Check redirect URL
kubectl get deployment myapp -o yaml | grep REDIRECT_URL

# Should match: https://myapp.cat-herding.net/oauth2/callback
```

### Issue: 503 Service Unavailable

**Symptom**: Cannot access application

**Causes**:
- oauth2-proxy sidecar not running
- App container not running
- Service not routing to correct port

**Fix**:
```bash
# Check pod status
kubectl get pods -l app=myapp

# Check both containers are running
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].name}'

# Check Service
kubectl get svc myapp -o yaml
# Verify port 4180 is listed
```

### Issue: User Headers Not Available

**Symptom**: Application can't read user identity

**Causes**:
- Application reading wrong headers
- oauth2-proxy not injecting headers

**Fix**:
```bash
# Check oauth2-proxy config
kubectl get configmap oauth2-proxy-sidecar-config -o yaml

# Verify these are set:
# pass_user_headers = true
# set_xauthrequest = true
```

## Migration from Centralized Auth

If migrating from the old centralized ext_authz pattern:

1. **Deploy new infrastructure**:
   ```bash
   ./scripts/setup.sh
   ```

2. **Migrate one app at a time**:
   ```bash
   ./scripts/add-sidecar.sh app1 default 8080 app1.cat-herding.net
   ```

3. **Verify app works** before migrating next

4. **After all apps migrated**, remove old resources:
   - Delete centralized oauth2-proxy Deployment
   - Delete ext-authz EnvoyFilter
   - Delete auth VirtualService

5. **Clean up** old configuration

## Future Enhancements

Possible improvements to this architecture:

1. **Automatic sidecar injection** via mutating webhook
2. **Shared session store** with Redis for larger deployments
3. **Custom error pages** per application
4. **Rate limiting** at oauth2-proxy level
5. **Multiple OAuth providers** per app (provider selection page)
6. **Session analytics** and monitoring dashboard

## References

- [oauth2-proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Istio Gateway](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [Kubernetes Sidecar Pattern](https://kubernetes.io/docs/concepts/workloads/pods/#workload-resources-for-managing-pods)
- [OAuth 2.0 RFC](https://datatracker.ietf.org/doc/html/rfc6749)

**Example**:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: example-app
  namespace: example-app
spec:
  hosts:
  - "example-app.cat-herding.net"
  gateways:
  - istio-system/cat-herding-gateway
  http:
  - route:
    - destination:
        host: example-app.example-app.svc.cluster.local
```

**Per-App Pattern**:
- Each app gets its own VirtualService
- Routes specific hostname to app service
- Uses shared `cat-herding-gateway`

### 5. AuthorizationPolicies

**Purpose**: Enforce authentication requirements per app

**Type**: CUSTOM (defers to ext_authz)

**Selector**: Targets pods with label `auth.cat-herding.net/enabled: "true"`

**Why Per-App Policies?**:
- Opt-in model: apps explicitly enable auth
- Flexibility: some apps can exclude specific paths (e.g., health checks)
- Granular control: different auth rules per app if needed

**Alternative Approach**:
The EnvoyFilter already checks ALL requests globally. AuthorizationPolicies provide additional control and documentation.

## Authentication Flow (Detailed)

### First Request (Unauthenticated User)

```
1. User visits: https://chat.cat-herding.net
   └─> DNS resolves to Istio ingress LoadBalancer IP

2. Request hits Istio Ingress Gateway
   └─> TLS terminated with wildcard cert
   └─> EnvoyFilter ext_authz intercepts request

3. Envoy calls oauth2-proxy auth check:
   POST http://oauth2-proxy.auth:4180/oauth2/auth
   Headers: Cookie, X-Forwarded-*
   
4. oauth2-proxy checks session:
   └─> No valid cookie found
   └─> Returns 302 redirect to GitHub OAuth

5. Envoy forwards 302 to client

6. Browser redirects to GitHub:
   https://github.com/login/oauth/authorize?
     client_id=...&
     redirect_uri=https://auth.cat-herding.net/oauth2/callback&
     state=...

7. User authenticates with GitHub

8. GitHub redirects to callback:
   https://auth.cat-herding.net/oauth2/callback?code=...&state=...

9. Request hits Istio → routes to oauth2-proxy (VirtualService)

10. oauth2-proxy handles callback:
    └─> Exchanges code for token with GitHub
    └─> Creates session
    └─> Sets encrypted cookie: _oauth2_proxy
        Domain: .cat-herding.net (SSO!)
        HttpOnly: true
        Secure: true
        SameSite: Lax
    └─> Returns 302 redirect to original URL: https://chat.cat-herding.net

11. Browser follows redirect with cookie

12. Request hits Istio again
    └─> EnvoyFilter calls oauth2-proxy auth check
    └─> oauth2-proxy validates cookie
    └─> Returns 202 with user headers:
        X-Auth-Request-User: githubuser
        X-Auth-Request-Email: user@example.com

13. Envoy forwards request to backend with headers

14. Backend receives authenticated request
```

### Subsequent Requests (Authenticated User)

```
1. User visits: https://dsa.cat-herding.net
   └─> Browser includes cookie (domain: .cat-herding.net)

2. Request hits Istio Ingress Gateway
   └─> EnvoyFilter calls oauth2-proxy auth check

3. oauth2-proxy validates cookie:
   └─> Cookie is valid and not expired
   └─> Returns 202 with user headers

4. Envoy forwards request to backend

5. User is authenticated → SSO works!
```

## Security Model

### TLS/HTTPS

- **Wildcard Certificate**: `*.cat-herding.net`
- **Managed By**: cert-manager (Let's Encrypt or other CA)
- **Termination**: At Istio ingress gateway
- **Backend**: HTTP (within cluster, mTLS via Istio)

### Session Management

- **Storage**: Cookie-based (no external storage)
- **Encryption**: AES-256 (cookie secret)
- **Cookie Attributes**:
  - `HttpOnly`: Prevents JavaScript access
  - `Secure`: HTTPS only
  - `SameSite: Lax`: CSRF protection
  - `Domain: .cat-herding.net`: SSO across subdomains

### OAuth Token Handling

- **Access Token**: Not stored in cookie (too large)
- **Refresh Token**: Used by oauth2-proxy to refresh session
- **Token Expiry**: Automatic refresh every 1 hour
- **Revocation**: Delete cookie or restart oauth2-proxy

### Network Security

- **Ingress**: Only through Istio gateway (TLS required)
- **Internal**: Istio mTLS encrypts pod-to-pod traffic
- **oauth2-proxy**: ClusterIP service (not exposed externally)
- **Backend Apps**: ClusterIP services (not exposed externally)

## Scalability

### oauth2-proxy

- **Stateless**: Can scale horizontally
- **Replicas**: 2 (HA setup)
- **No Database**: Cookie-based sessions
- **Resource Limits**: 500m CPU, 256Mi memory

### Istio Ingress Gateway

- **Replicas**: Managed by Istio operator (typically 2-3)
- **Auto-scaling**: HPA configured
- **Connection Pooling**: Envoy handles efficiently

### Backend Applications

- **Independent Scaling**: Each app scales independently
- **No Auth Logic**: Apps don't need to implement OAuth
- **Simple Integration**: Just read headers

## Observability

### Logging

**oauth2-proxy Logs**:
- Authentication events (success/failure)
- User identity (email, username)
- OAuth provider
- Requested URL
- Source IP

**Format**:
```json
{
  "timestamp": "2025-11-27T10:00:00Z",
  "level": "info",
  "msg": "AuthSuccess",
  "user": "githubuser",
  "email": "user@example.com",
  "provider": "github",
  "url": "https://chat.cat-herding.net/",
  "client_ip": "1.2.3.4"
}
```

**Istio Access Logs**:
- All requests through ingress gateway
- Response codes, latencies
- Upstream services

### Metrics

**oauth2-proxy Metrics** (Prometheus format on port 44180):
- `oauth2_proxy_requests_total`: Total requests
- `oauth2_proxy_authentication_total{result="success|failure"}`: Auth attempts
- `oauth2_proxy_upstream_requests_total`: Upstream requests

**Istio Metrics**:
- Request rate, error rate, latency (RED metrics)
- Service-to-service traffic
- ext_authz check latencies

### Tracing

- **Distributed Tracing**: Via Istio (Jaeger/Zipkin)
- **Trace Propagation**: Headers forwarded through ext_authz
- **End-to-End Visibility**: User request → auth check → backend

## Failure Modes

### oauth2-proxy Down

**Behavior**: `failure_mode_allow: false` in EnvoyFilter

- All requests return **503 Service Unavailable**
- No traffic reaches backends
- Users cannot authenticate or access apps

**Mitigation**:
- 2 replicas with pod anti-affinity
- Health checks and auto-restart
- Monitor oauth2-proxy availability

### OAuth Provider Down

**Behavior**:
- Existing sessions continue to work (cookie-based)
- New logins fail
- Token refresh fails (after expiry)

**Mitigation**:
- Long cookie expiry (7 days)
- Multiple OAuth providers configured
- Clear error messages to users

### Certificate Expiry

**Behavior**:
- HTTPS fails
- Browsers show certificate error
- No traffic can reach apps

**Mitigation**:
- cert-manager auto-renewal
- Monitoring for certificate expiry
- Alerts 30 days before expiration

### Envoy Config Propagation Delay

**Behavior**:
- Brief period where config is inconsistent
- Some ingress pods have old config

**Mitigation**:
- Wait 10-30s after applying EnvoyFilter
- Gradual rollouts
- Test in dev environment first

## Comparison with Alternatives

### vs. Per-App OAuth Implementation

| Aspect | Centralized (This) | Per-App |
|--------|-------------------|---------|
| Implementation | Once | Every app |
| Maintenance | Centralized | Distributed |
| SSO | Yes (.cat-herding.net) | No (per-app sessions) |
| User Experience | Seamless | Login per app |
| Security Updates | One place | Every app |
| Language Agnostic | Yes | Depends on app |

### vs. Istio RequestAuthentication (JWT)

| Aspect | oauth2-proxy | JWT-based |
|--------|--------------|-----------|
| Session Type | Cookie | Bearer token |
| Client Support | Browser (automatic) | API clients |
| Token Refresh | Automatic | Manual |
| Social Login | Easy | Requires IdP integration |
| Use Case | Web apps | APIs, mobile apps |

### vs. Kubernetes Ingress + OAuth2 Proxy

| Aspect | Istio ext_authz | Ingress Annotations |
|--------|-----------------|---------------------|
| Integration | Native (EnvoyFilter) | Annotations |
| Flexibility | High | Limited |
| Observability | Istio metrics/tracing | Basic |
| Multi-cluster | Yes (Istio mesh) | No |

## Best Practices

1. **Cookie Secret Rotation**: Rotate cookie secret periodically (invalidates sessions)
2. **Monitor Auth Metrics**: Track auth success/failure rates
3. **Health Checks Exclusion**: Exempt `/health`, `/readyz` from auth
4. **Graceful Degradation**: Implement fallback for auth failures
5. **Test in Dev**: Always test auth changes in dev overlay first
6. **Document OAuth Apps**: Maintain list of OAuth apps and their configs
7. **User Logout**: Provide logout endpoint: `https://auth.cat-herding.net/oauth2/sign_out`
8. **Session Timeout**: Adjust cookie expiry based on security requirements
9. **Audit Logs**: Forward oauth2-proxy logs to SIEM for audit

## Troubleshooting Guide

See [SETUP.md](SETUP.md) for detailed troubleshooting steps.

## References

- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Istio External Authorization](https://istio.io/latest/docs/tasks/security/authorization/authz-custom/)
- [Envoy ext_authz Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)
