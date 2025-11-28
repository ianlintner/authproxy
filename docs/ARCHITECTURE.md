# Architecture: SSO Social Login Proxy Gateway

## Overview

This architecture implements a centralized authentication gateway for AKS applications using:

- **Istio** for traffic management and external authorization
- **oauth2-proxy** as the authentication proxy
- **Social OAuth providers** (GitHub, Google, LinkedIn, Microsoft)
- **Cookie-based SSO** across all `*.cat-herding.net` subdomains

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
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                  Istio Ingress Gateway                             │
│                  (istio-ingressgateway)                            │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  Gateway: *.cat-herding.net                              │    │
│  │  - TLS Termination (wildcard cert)                       │    │
│  │  - HTTP → HTTPS redirect                                 │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  EnvoyFilter: ext_authz                                  │    │
│  │  - Intercepts ALL requests                               │    │
│  │  - Calls oauth2-proxy for auth check                     │    │
│  │  - Path: /oauth2/auth                                    │    │
│  │  - Forwards auth headers to upstream                     │    │
│  └───────────────────┬──────────────────────────────────────┘    │
└──────────────────────┼───────────────────────────────────────────┘
                       │
                       │ Auth Check Request
                       │
        ┌──────────────▼───────────────┐
        │                              │
        │  Is session cookie valid?    │
        │                              │
        └──────┬────────────────┬──────┘
               │                │
        No     │                │ Yes
               │                │
┌──────────────▼─────────────┐  │  ┌────────────────────────────┐
│  oauth2-proxy              │  │  │  Forward to upstream       │
│  (auth namespace)          │  │  │  with user headers:        │
│                            │  │  │  - X-Auth-Request-Email    │
│  Port 4180: OAuth callback │  │  │  - X-Auth-Request-User     │
│  Port 4181: Auth check API │  └─▶│  - X-Auth-Request-*        │
│                            │     └────────────┬───────────────┘
│  ┌──────────────────────┐ │                  │
│  │ Cookie: .cat-herding │ │                  │
│  │ Domain: SSO enabled  │ │                  │
│  └──────────────────────┘ │                  │
│                            │                  │
│  Redirect to OAuth?        │                  │
└────────────┬───────────────┘                  │
             │                                  │
             │ Yes, redirect                    │
             │                                  │
┌────────────▼───────────────┐                 │
│  Social OAuth Provider     │                 │
│  - GitHub                  │                 │
│  - Google                  │                 │
│  - LinkedIn                │                 │
│  - Microsoft               │                 │
│                            │                 │
│  User logs in with social  │                 │
│  account                   │                 │
└────────────┬───────────────┘                 │
             │                                  │
             │ OAuth callback                   │
             │                                  │
┌────────────▼───────────────┐                 │
│  oauth2-proxy              │                 │
│  /oauth2/callback          │                 │
│                            │                 │
│  - Exchange code for token │                 │
│  - Create session          │                 │
│  - Set encrypted cookie    │                 │
│  - Redirect to original URL│                 │
└────────────────────────────┘                 │
                                                │
                     ┌──────────────────────────▼─────────┐
                     │  Backend Applications               │
                     │  (with auth.cat-herding.net/        │
                     │   enabled: "true" label)            │
                     │                                     │
                     │  - chat.cat-herding.net             │
                     │  - dsa.cat-herding.net              │
                     │  - example-app.cat-herding.net      │
                     │                                     │
                     │  Apps read user identity from       │
                     │  request headers                    │
                     └─────────────────────────────────────┘
```

## Components

### 1. Istio Ingress Gateway

**Purpose**: Entry point for all external traffic

**Configuration**:
- **Gateway Resource**: Defines `*.cat-herding.net` hosts
- **TLS**: Uses wildcard certificate `cat-herding-wildcard-tls`
- **Ports**: 80 (HTTP → HTTPS redirect), 443 (HTTPS)

**Key Features**:
- Wildcard DNS support
- Automatic TLS termination
- HTTP to HTTPS redirection

### 2. EnvoyFilter (ext_authz)

**Purpose**: External authorization filter for authentication checks

**Location**: `istio-system` namespace, applied to `istio-ingressgateway`

**How It Works**:
1. Intercepts every HTTP request at the ingress gateway
2. Sends authentication check to oauth2-proxy (`/oauth2/auth` endpoint)
3. If oauth2-proxy returns 2xx: forwards request with user headers
4. If oauth2-proxy returns 302: sends redirect to client (login flow)
5. If oauth2-proxy returns error: returns 503 to client

**Configuration**:
```yaml
server_uri: http://oauth2-proxy.auth.svc.cluster.local:4180
path_prefix: /oauth2/auth
failure_mode_allow: false  # Deny by default if auth check fails
```

**Headers Passed to Upstream**:
- `X-Auth-Request-User`
- `X-Auth-Request-Email`
- `X-Auth-Request-Preferred-Username`
- `Authorization` (if configured)

### 3. oauth2-proxy

**Purpose**: Authentication proxy and session manager

**Deployment**: 2 replicas in `auth` namespace

**Ports**:
- **4180**: Main HTTP endpoint (OAuth callback, auth checks)
- **44180**: Metrics endpoint (Prometheus)

**Configuration**:
- **Provider**: GitHub (configurable for Google, Azure AD B2C, OIDC)
- **Cookie Domain**: `.cat-herding.net` (enables SSO)
- **Cookie Expiry**: 7 days (168h)
- **Cookie Refresh**: 1 hour
- **Session Storage**: Cookie-based (stateless)

**Key Features**:
- Stateless operation (no Redis required)
- Encrypted session cookies
- Automatic token refresh
- Support for multiple OAuth providers

**Authentication Flow**:
1. Receives auth check request from Envoy: `GET /oauth2/auth`
2. Checks if request has valid session cookie
3. If valid: returns 202 with user headers
4. If invalid: returns 302 redirect to OAuth provider
5. User logs in at OAuth provider
6. OAuth provider redirects to: `https://auth.cat-herding.net/oauth2/callback?code=...`
7. oauth2-proxy exchanges code for token
8. Sets encrypted session cookie (domain: `.cat-herding.net`)
9. Redirects user back to original URL
10. Subsequent requests include cookie → authenticated

### 4. VirtualServices

**Purpose**: Route traffic from hostnames to backend services

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
