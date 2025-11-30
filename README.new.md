# OAuth2 Sidecar for Kubernetes

<p align="center">
  <strong>Simple, secure OAuth2 authentication for your Kubernetes applications</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#installation">Installation</a> •
  <a href="#documentation">Documentation</a> •
  <a href="#examples">Examples</a>
</p>

---

## What is OAuth2 Sidecar?

OAuth2 Sidecar is a **turnkey authentication solution** for Kubernetes applications that uses the sidecar pattern with [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) and Istio. Instead of implementing OAuth2 in every application, you simply add a sidecar container that handles authentication for you.

### The Problem

Adding authentication to Kubernetes applications is repetitive and error-prone:
- ❌ Implementing OAuth2 in every app
- ❌ Managing tokens and sessions
- ❌ Keeping authentication libraries up to date
- ❌ Ensuring consistent security across services

### The Solution

OAuth2 Sidecar provides a **plug-and-play authentication layer**:
- ✅ Add one sidecar container to your deployment
- ✅ OAuth2 authentication handled automatically  
- ✅ Single sign-on (SSO) across all your apps
- ✅ User identity injected via HTTP headers
- ✅ No code changes required

## Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────┐
│ Istio Gateway   │  ← TLS termination
│  *.example.com  │
└────────┬────────┘
         │
         ▼
┌──────────────────────┐
│   Service :4180      │
└──────────┬───────────┘
           │
           ▼
    ┌──────────────┐
    │     Pod      │
    ├──────────────┤
    │ oauth2-proxy │ :4180 ← Authenticates requests
    │   (sidecar)  │
    ├──────────────┤
    │      ↓       │
    │   Your App   │ :8080 ← Receives authenticated requests
    └──────────────┘
```

### How It Works

1. **User visits your app** → Request hits Istio Gateway
2. **Gateway routes to service** → Points to oauth2-proxy sidecar (port 4180)
3. **Sidecar checks authentication**:
   - ✅ **Authenticated** → Proxies request to app with user headers
   - ❌ **Not authenticated** → Redirects to OAuth provider (GitHub, Google, etc.)
4. **User logs in** → OAuth provider redirects back with token
5. **Sidecar creates session** → Encrypted cookie enables SSO
6. **Request reaches your app** → With user identity in headers

## Features

- 🔐 **Multiple OAuth Providers** - GitHub, Google, Azure AD, generic OIDC
- 🔄 **Single Sign-On** - One login works across all your applications
- 🎯 **Zero Code Changes** - Works with any HTTP application
- 🛡️ **Istio Integration** - Leverages Istio for routing and TLS
- 🎨 **Custom Branding** - Customize login pages with your logo and colors
- 📊 **User Headers** - App receives `X-Auth-User`, `X-Auth-Email`, etc.
- 🔒 **Secure by Default** - Encrypted cookies, secure sessions
- 📦 **Stateless** - No Redis or database required
- ⚡ **Production Ready** - Resource limits, health checks, security context

## Quick Start

### Prerequisites

- Kubernetes cluster (1.19+)
- Istio installed (1.10+)
- OAuth app registered (GitHub, Google, etc.)
- Wildcard TLS certificate
- DNS pointing to Istio ingress

### 1-Minute Install

```bash
# Clone the repository
git clone https://github.com/ianlintner/authproxy.git
cd authproxy

# Run the interactive installer
./install.sh
```

The installer will:
1. Check prerequisites
2. Ask for your domain and OAuth credentials
3. Deploy OAuth2 Sidecar to your cluster
4. Provide next steps

### Manual Install (Helm)

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set oauth.provider=github \
  --set oauth.clientID=YOUR_CLIENT_ID \
  --set oauth.clientSecret=YOUR_CLIENT_SECRET \
  --set oauth.cookieSecret=$(openssl rand -base64 32) \
  --set istio.gateway.tls.credentialName=wildcard-tls-secret
```

### Manual Install (kubectl)

```bash
# Create secret
kubectl create secret generic oauth2-proxy-secret \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --from-literal=cookie-secret=$(openssl rand -base64 32)

# Apply configuration
kubectl apply -k k8s/base/
```

## Installation

### Helm Chart (Recommended)

The Helm chart provides the most flexible installation:

```bash
# Install with default values
helm install oauth2-sidecar ./helm/oauth2-sidecar -f values.yaml

# Or use command-line overrides
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=mycompany.com \
  --set oauth.provider=google \
  --set oauth.clientID=xxx \
  --set oauth.clientSecret=yyy
```

See [Helm Chart Documentation](./helm/oauth2-sidecar/README.md) for full configuration options.

### Kustomize

Use kustomize for GitOps workflows:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - github.com/ianlintner/authproxy/k8s/base?ref=main

namespace: default

configMapGenerator:
  - name: oauth2-proxy-sidecar-config
    behavior: merge
    literals:
      - domain=mycompany.com

secretGenerator:
  - name: oauth2-proxy-secret
    literals:
      - client-id=xxx
      - client-secret=yyy
      - cookie-secret=zzz
```

Then apply:

```bash
kubectl apply -k .
```

## Usage

### Add Authentication to Your App

1. **Add the sidecar container**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        # Your application
        - name: app
          image: my-app:latest
          ports:
            - containerPort: 8080
        
        # OAuth2 Proxy sidecar
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
          args:
            - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
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
            - name: OAUTH2_PROXY_UPSTREAMS
              value: "http://127.0.0.1:8080"
            - name: OAUTH2_PROXY_REDIRECT_URL
              value: "https://my-app.example.com/oauth2/callback"
          ports:
            - containerPort: 4180
          volumeMounts:
            - name: oauth2-config
              mountPath: /etc/oauth2-proxy
              readOnly: true
      volumes:
        - name: oauth2-config
          configMap:
            name: oauth2-proxy-sidecar-config
```

2. **Create Service** (point to sidecar port):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  selector:
    app: my-app
  ports:
    - port: 4180
      targetPort: 4180
```

3. **Create VirtualService** for routing:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
    - "my-app.example.com"
  gateways:
    - istio-system/oauth2-gateway
  http:
    - route:
        - destination:
            host: my-app
            port:
              number: 4180
```

4. **Access your app**: https://my-app.example.com 🎉

### Access User Information

Your app receives authenticated user information via HTTP headers:

```bash
X-Auth-Request-User: john.doe@example.com
X-Auth-Request-Email: john.doe@example.com
X-Auth-Request-Preferred-Username: johndoe
X-Forwarded-User: john.doe@example.com
Authorization: Bearer <access-token>
```

Example in your app:

```python
# Python/Flask
@app.route('/profile')
def profile():
    user_email = request.headers.get('X-Auth-Request-Email')
    return f'Hello, {user_email}!'
```

```javascript
// Node.js/Express
app.get('/profile', (req, res) => {
  const userEmail = req.headers['x-auth-request-email'];
  res.send(`Hello, ${userEmail}!`);
});
```

```go
// Go
func profileHandler(w http.ResponseWriter, r *http.Request) {
    userEmail := r.Header.Get("X-Auth-Request-Email")
    fmt.Fprintf(w, "Hello, %s!", userEmail)
}
```

## Documentation

- 📖 [Helm Chart README](./helm/oauth2-sidecar/README.md) - Complete configuration reference
- 🏗️ [Architecture Guide](./docs/ARCHITECTURE.md) - Detailed architecture explanation
- ⚙️ [Configuration Guide](./docs/configuration.md) - All configuration options
- 🔧 [OAuth Providers](./docs/providers/) - Provider-specific setup guides
  - [GitHub](./docs/providers/github.md)
  - [Google](./docs/providers/google.md)
  - [Azure AD](./docs/providers/azure-ad.md)
  - [Generic OIDC](./docs/providers/oidc.md)
- 🐛 [Troubleshooting](./docs/troubleshooting.md) - Common issues and solutions
- 🔒 [Security Best Practices](./docs/security.md) - Production deployment guide

## Examples

Complete working examples for different scenarios:

- [**simple-app/**](./examples/simple-app/) - Minimal working example
- [**github-org/**](./examples/github-org/) - GitHub with organization restriction
- [**google-workspace/**](./examples/google-workspace/) - Google Workspace domain
- [**azure-ad/**](./examples/azure-ad/) - Azure Active Directory integration
- [**multi-app/**](./examples/multi-app/) - Multiple apps with shared SSO
- [**custom-branding/**](./examples/custom-branding/) - Custom templates and logo
- [**external-secrets/**](./examples/external-secrets/) - External Secrets Operator integration

## Configuration

### OAuth Providers

<details>
<summary><b>GitHub</b></summary>

1. Create OAuth App: https://github.com/settings/developers
2. Set callback URL: `https://app.example.com/oauth2/callback`
3. Configure:

```yaml
oauth:
  provider: github
  clientID: "your-client-id"
  clientSecret: "your-client-secret"
  github:
    org: "my-org"  # Optional: restrict to org
    team: "my-team"  # Optional: restrict to team
```
</details>

<details>
<summary><b>Google</b></summary>

1. Create OAuth 2.0 Client: https://console.cloud.google.com/apis/credentials
2. Add authorized redirect URI: `https://app.example.com/oauth2/callback`
3. Configure:

```yaml
oauth:
  provider: google
  clientID: "xxx.apps.googleusercontent.com"
  clientSecret: "your-client-secret"
  google:
    hostedDomain: "mycompany.com"  # Optional: restrict to domain
```
</details>

<details>
<summary><b>Azure AD</b></summary>

1. Register app: https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps
2. Add redirect URI: `https://app.example.com/oauth2/callback`
3. Configure:

```yaml
oauth:
  provider: azure
  clientID: "your-client-id"
  clientSecret: "your-client-secret"
  azure:
    tenant: "your-tenant-id"
```
</details>

<details>
<summary><b>Generic OIDC</b></summary>

```yaml
oauth:
  provider: oidc
  clientID: "your-client-id"
  clientSecret: "your-client-secret"
  oidc:
    issuerURL: "https://auth.example.com"
    extraScopes:
      - profile
      - email
```
</details>

## Troubleshooting

### Pods not starting

```bash
kubectl get pods
kubectl logs <pod-name> -c oauth2-proxy
```

### Authentication not working

1. Check OAuth app callback URL matches your domain
2. Verify secret exists: `kubectl get secret oauth2-proxy-secret -o yaml`
3. Check oauth2-proxy logs for errors

### 502 Bad Gateway

- Ensure app container port matches `OAUTH2_PROXY_UPSTREAMS`
- Check app container is running: `kubectl logs <pod-name> -c app`

### TLS Certificate errors

```bash
# Verify certificate exists
kubectl get secret -n istio-system <tls-secret-name>

# Check gateway configuration
kubectl get gateway -n istio-system -o yaml
```

See [Troubleshooting Guide](./docs/troubleshooting.md) for more solutions.

## Migration from Old Setup

If you're migrating from the centralized OAuth2 proxy setup, see [MIGRATION.md](./MIGRATION.md) for step-by-step instructions.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

### Development

```bash
# Clone repository
git clone https://github.com/ianlintner/authproxy.git
cd authproxy

# Make changes...

# Test Helm chart
helm lint ./helm/oauth2-sidecar
helm template ./helm/oauth2-sidecar

# Test on cluster
helm install test ./helm/oauth2-sidecar --dry-run --debug
```

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Acknowledgments

- [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) - The excellent OAuth2 reverse proxy
- [Istio](https://istio.io/) - Service mesh platform
- All contributors who have helped improve this project

## Support

- 📖 [Documentation](https://github.com/ianlintner/authproxy)
- 🐛 [Issue Tracker](https://github.com/ianlintner/authproxy/issues)
- 💬 [Discussions](https://github.com/ianlintner/authproxy/discussions)
- 📧 Email: ian@lintner.com

---

<p align="center">
  Made with ❤️ for the Kubernetes community
</p>
