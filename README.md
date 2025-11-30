# OAuth2 Sidecar Proxy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20+-326CE5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Istio](https://img.shields.io/badge/Istio-1.14+-466BB0.svg?logo=istio&logoColor=white)](https://istio.io/)
[![Helm](https://img.shields.io/badge/Helm-3.0+-0F1689.svg?logo=helm&logoColor=white)](https://helm.sh/)
[![Documentation](https://img.shields.io/badge/docs-MkDocs-blue.svg?logo=materialformkdocs)](https://ianlintner.github.io/authproxy/)
[![GitHub](https://img.shields.io/github/stars/ianlintner/authproxy?style=social)](https://github.com/ianlintner/authproxy)

> Simple, secure OAuth2 authentication for Kubernetes applications using the **sidecar pattern**. 

Each application gets its own `oauth2-proxy` container that handles authentication transparently—no complex configuration needed.

## ✨ Key Features

- 🔒 **Secure by Default** - OAuth2/OIDC authentication with industry best practices
- 🎯 **Sidecar Pattern** - Isolated authentication per application
- 🚀 **Zero Application Changes** - Drop-in authentication for any HTTP service
- 🌐 **Single Sign-On** - Share sessions across all `*.example.com` apps
- 🎨 **Customizable UI** - Branded sign-in pages with Tailwind CSS
- 📊 **Observable** - Prometheus metrics, health checks, audit logs
- 🔄 **Multi-Provider** - GitHub, Google, Azure AD, Generic OIDC
- 🛡️ **Security Hardened** - Non-root containers, read-only filesystems, minimal privileges

## 📚 Documentation

**📖 Full documentation: [https://ianlintner.github.io/authproxy/](https://ianlintner.github.io/authproxy/)**

| Topic | Description |
|-------|-------------|
| [Quick Start](https://ianlintner.github.io/authproxy/getting-started/quickstart/) | Get running in 5 minutes |
| [Architecture](https://ianlintner.github.io/authproxy/architecture/overview/) | How it works with diagrams |
| [Installation](https://ianlintner.github.io/authproxy/getting-started/installation/) | Detailed setup guide |
| [Adding Apps](https://ianlintner.github.io/authproxy/guide/adding-apps/) | Protect your applications |
| [OAuth Providers](https://ianlintner.github.io/authproxy/providers/github/) | GitHub, Google, Azure AD |
| [Configuration](https://ianlintner.github.io/authproxy/reference/configuration/) | All config options |
| [Troubleshooting](https://ianlintner.github.io/authproxy/guide/troubleshooting/) | Common issues & solutions |

## 🚀 Quick Start

### Prerequisites

- Kubernetes 1.20+ with `kubectl` access
- Istio 1.14+ service mesh installed
- Helm 3 installed
- Domain with DNS/TLS configured
- OAuth app registered (e.g., GitHub OAuth App)

### Install in 3 Steps

#### 1. Create OAuth Application

<details>
<summary><b>GitHub</b></summary>

1. Go to GitHub Settings → Developer settings → OAuth Apps
2. Click **New OAuth App**
3. Set **Homepage URL**: `https://example.com`
4. Set **Authorization callback URL**: `https://auth.example.com/oauth2/callback`
5. Save **Client ID** and generate a **Client Secret**

</details>

<details>
<summary><b>Google</b></summary>

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create project → APIs & Services → Credentials
3. Create **OAuth 2.0 Client ID** (Web application)
4. Add **Authorized redirect URI**: `https://auth.example.com/oauth2/callback`
5. Save **Client ID** and **Client Secret**

</details>

#### 2. Install with Helm

```bash
# Clone the repository
git clone https://github.com/ianlintner/authproxy.git
cd authproxy

# Install the helm chart
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set cookieDomain=.example.com \
  --set oauth.provider=github \
  --set oauth.clientID=Ov23li1234567890abcd \
  --set oauth.clientSecret=1234567890abcdef1234567890abcdef12345678 \
  --set istio.gateway.existingGateway=your-gateway \
  --namespace default
```

<details>
<summary>Or create a values file</summary>

```yaml
# values.yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: github
  clientID: Ov23li1234567890abcd
  clientSecret: 1234567890abcdef1234567890abcdef12345678
  
istio:
  gateway:
    existingGateway: your-gateway
```

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  -f values.yaml \
  --namespace default
```

</details>

#### 3. Deploy Example Application

```bash
# Deploy the example app
kubectl apply -k k8s/apps/example-app/

# Check deployment
kubectl get pods -l app=example-app
```

#### 4. Test It Out

```bash
# Visit your app (will redirect to GitHub/Google login)
open https://example-app.example.com
```

You should see:
1. **Sign-in page** with your OAuth provider button
2. **OAuth consent** screen (first time only)
3. **Your application** - authenticated! 🎉

## 🏗️ Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────┐
│  Istio Gateway  │
│   (TLS Term)    │
└───────┬─────────┘
        │
        ▼
┌────────────────────────────────┐
│     Kubernetes Service         │
│        (port 4180)             │
└───────┬────────────────────────┘
        │
        ▼
┌────────────────────────────────┐
│           Pod                  │
│  ┌──────────────────────────┐ │
│  │  OAuth2 Proxy Sidecar    │ │
│  │  :4180                   │ │
│  └─────────┬────────────────┘ │
│            │ localhost         │
│            ▼                   │
│  ┌──────────────────────────┐ │
│  │  Your Application        │ │
│  │  :8080                   │ │
│  └──────────────────────────┘ │
└────────────────────────────────┘
```

### How It Works

1. **Traffic arrives** at Istio Gateway with TLS termination
2. **VirtualService routes** to Service port 4180
3. **OAuth2 Proxy sidecar** receives request:
   - ❌ No cookie? → Redirect to OAuth provider sign-in
   - ✅ Valid cookie? → Proxy to app on `localhost:8080`
4. **Application receives** request with injected headers:
   - `X-Auth-Request-User`: `john.doe`
   - `X-Auth-Request-Email`: `john.doe@example.com`
   - `X-Auth-Request-Access-Token`: `gho_xxxx...`

### Why Sidecar Pattern?

| Benefit | Description |
|---------|-------------|
| **Simple** | No complex Istio ext_authz or EnvoyFilter configuration |
| **Isolated** | Each app has its own OAuth configuration |
| **Debuggable** | Logs and metrics co-located with your app |
| **Flexible** | Different OAuth providers per application |
| **Portable** | Easy to migrate apps between clusters |

See [Architecture Documentation](https://ianlintner.github.io/authproxy/architecture/overview/) for detailed diagrams.

## 🔧 Configuration

### OAuth Providers

Configure your OAuth provider in the Helm values:

=== "GitHub"
    ```yaml
    oauth:
      provider: github
      clientID: Ov23li1234567890
      clientSecret: your-secret
      github:
        org: "my-company"  # Optional: restrict to org
        team: "engineering"  # Optional: restrict to team
    ```

=== "Google"
    ```yaml
    oauth:
      provider: google
      clientID: 1234567890-abc123.apps.googleusercontent.com
      clientSecret: your-secret
      google:
        hostedDomain: "example.com"  # Optional: restrict to domain
    ```

=== "Azure AD"
    ```yaml
    oauth:
      provider: azure
      clientID: your-app-id
      clientSecret: your-secret
      azure:
        tenant: your-tenant-id
    ```

See [OAuth Provider Documentation](https://ianlintner.github.io/authproxy/providers/github/) for detailed setup guides.

### Custom Sign-in Pages

Customize the sign-in page with your branding:

```yaml
customTemplates:
  enabled: true
  brandName: "My Company SSO"
  logo: "<base64-encoded-logo>"
```

See [Custom Templates Guide](https://ianlintner.github.io/authproxy/guide/custom-templates/).

### Advanced Configuration

```yaml
# Session settings
session:
  cookieExpire: 168h  # 7 days
  cookieRefresh: 1h   # Refresh interval

# Email restrictions
email:
  domains:
    - "example.com"
    - "partner.com"

# Extra arguments to oauth2-proxy
extraArgs:
  - --skip-auth-regex=^/health
  - --ssl-upstream-insecure-skip-verify
```

Full configuration reference: [Configuration Options](https://ianlintner.github.io/authproxy/reference/configuration/)

## 🚀 Adding Your Applications

### Option 1: Use the Helper Script

```bash
./scripts/add-app.sh <app-name> <namespace> <app-port> <domain>

# Example:
./scripts/add-app.sh my-api default 8080 api.example.com
```

### Option 2: Manual Configuration

Add the oauth2-proxy sidecar to your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      # OAuth2 Proxy sidecar
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
        args:
          - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
        env:
          - name: OAUTH2_PROXY_UPSTREAMS
            value: "http://127.0.0.1:8080"
        ports:
          - containerPort: 4180
        volumeMounts:
          - name: oauth2-proxy-config
            mountPath: /etc/oauth2-proxy
          - name: oauth2-proxy-templates
            mountPath: /templates
      
      # Your application
      - name: app
        image: my-app:latest
        ports:
          - containerPort: 8080
      
      volumes:
        - name: oauth2-proxy-config
          configMap:
            name: oauth2-proxy-sidecar-config
        - name: oauth2-proxy-templates
          configMap:
            name: oauth2-proxy-templates
```

Complete guide: [Adding Applications](https://ianlintner.github.io/authproxy/guide/adding-apps/)

## 🔍 Accessing User Information

Your application automatically receives user information via HTTP headers:

### Available Headers

| Header | Description | Example |
|--------|-------------|---------|
| `X-Auth-Request-User` | Username | `john.doe` |
| `X-Auth-Request-Email` | Email address | `john.doe@example.com` |
| `X-Auth-Request-Preferred-Username` | Preferred username | `johndoe` |
| `X-Auth-Request-Access-Token` | OAuth access token | `gho_xxxx...` |
| `X-Forwarded-User` | User identifier | `john.doe` |
| `X-Forwarded-Email` | Email address | `john.doe@example.com` |
| `Authorization` | Bearer token | `Bearer gho_xxxx...` |

### Code Examples

=== "Python / Flask"
    ```python
    from flask import Flask, request
    
    app = Flask(__name__)
    
    @app.route('/')
    def index():
        user = request.headers.get('X-Auth-Request-User')
        email = request.headers.get('X-Auth-Request-Email')
        return f'Hello {user} ({email})!'
    
    @app.route('/admin')
    def admin():
        email = request.headers.get('X-Auth-Request-Email')
        if not email.endswith('@example.com'):
            return 'Forbidden', 403
        return 'Admin Panel'
    ```

=== "Node.js / Express"
    ```javascript
    const express = require('express');
    const app = express();
    
    app.get('/', (req, res) => {
      const user = req.headers['x-auth-request-user'];
      const email = req.headers['x-auth-request-email'];
      res.send(`Hello ${user} (${email})!`);
    });
    
    app.get('/admin', (req, res) => {
      const email = req.headers['x-auth-request-email'];
      if (!email.endsWith('@example.com')) {
        return res.status(403).send('Forbidden');
      }
      res.send('Admin Panel');
    });
    
    app.listen(8080);
    ```

=== "Go"
    ```go
    package main
    
    import (
        "fmt"
        "net/http"
    )
    
    func handler(w http.ResponseWriter, r *http.Request) {
        user := r.Header.Get("X-Auth-Request-User")
        email := r.Header.Get("X-Auth-Request-Email")
        fmt.Fprintf(w, "Hello %s (%s)!", user, email)
    }
    
    func main() {
        http.HandleFunc("/", handler)
        http.ListenAndServe(":8080", nil)
    }
    ```

## 📊 Monitoring & Observability

### Health Checks

OAuth2-proxy exposes health endpoints:

- `GET /ping` - Liveness check
- `GET /ready` - Readiness check

### Prometheus Metrics

Metrics available at `/metrics`:

```
oauth2_proxy_requests_total
oauth2_proxy_authentication_attempts_total
oauth2_proxy_authentication_failures_total
oauth2_proxy_cookies_expired_total
```

### Logs

View sidecar logs:

```bash
# View oauth2-proxy logs
kubectl logs -n default <pod-name> -c oauth2-proxy

# View application logs
kubectl logs -n default <pod-name> -c app

# Follow both
kubectl logs -n default <pod-name> --all-containers -f
```

## 🐛 Troubleshooting

### Common Issues

<details>
<summary><b>Redirect loop / Endless redirects</b></summary>

**Cause**: Callback URL mismatch

**Solution**: Ensure callback URL in OAuth provider matches:
```
https://auth.example.com/oauth2/callback
```

Check deployment env var:
```bash
kubectl get deployment -o yaml | grep REDIRECT_URL
```

</details>

<details>
<summary><b>Cookie not persisting / Sign in every time</b></summary>

**Cause**: Cookie domain mismatch

**Solution**: Verify cookie domain is `.example.com`:
```bash
kubectl get configmap oauth2-proxy-sidecar-config -o yaml | grep cookie_domains
```

</details>

<details>
<summary><b>404 Not Found on protected paths</b></summary>

**Cause**: VirtualService routing to wrong port

**Solution**: Verify VirtualService routes to port 4180:
```bash
kubectl get virtualservice <app-name> -o yaml
```

Should have:
```yaml
destination:
  host: <app-name>
  port:
    number: 4180  # oauth2-proxy port
```

</details>

<details>
<summary><b>Connection refused to localhost:8080</b></summary>

**Cause**: Application not listening on localhost

**Solution**: Ensure app container listens on `0.0.0.0:8080` or `127.0.0.1:8080`

</details>

See [Troubleshooting Guide](https://ianlintner.github.io/authproxy/guide/troubleshooting/) for more solutions.

## 📁 Repository Structure

```
authproxy/
├── docs/                      # MkDocs documentation
│   ├── getting-started/      # Installation & quick start
│   ├── architecture/         # Architecture with diagrams
│   ├── guide/                # User guides
│   ├── providers/            # OAuth provider setup
│   └── reference/            # API & config reference
├── helm/
│   └── oauth2-sidecar/       # Helm chart
│       ├── templates/        # Kubernetes templates
│       ├── values.yaml       # Default values
│       └── Chart.yaml        # Chart metadata
├── k8s/
│   ├── base/                 # Base resources
│   │   ├── istio/           # Gateway, VirtualService
│   │   └── oauth2-proxy/    # ConfigMaps, templates
│   └── apps/
│       └── example-app/      # Complete working example
├── scripts/
│   ├── add-app.sh           # Add auth to existing apps
│   ├── setup.sh             # Initial cluster setup
│   └── validate.sh          # Validation checks
├── examples/                 # Example configurations
│   └── simple-app/          # Minimal example
├── mkdocs.yml               # Documentation config
└── README.md                # This file
```

## 🤝 Contributing

Contributions are welcome! Please see [Contributing Guide](https://ianlintner.github.io/authproxy/contributing/).

### Development Setup

```bash
# Clone repository
git clone https://github.com/ianlintner/authproxy.git
cd authproxy

# Install documentation dependencies
pip install -r docs/requirements.txt

# Serve docs locally
mkdocs serve

# Run validation
./scripts/validate.sh
