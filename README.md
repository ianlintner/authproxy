# OAuth2 Sidecar Proxy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20+-blue.svg)](https://kubernetes.io/)
[![Istio](https://img.shields.io/badge/Istio-1.14+-blue.svg)](https://istio.io/)
[![Documentation](https://img.shields.io/badge/docs-mkdocs-blue.svg)](https://ianlintner.github.io/authproxy/)

Simple, secure OAuth2 authentication for Kubernetes applications using the **sidecar pattern**. Each application gets its own `oauth2-proxy` container that handles authentication before requests reach your app.

## ✨ Features

- 🔒 **Secure OAuth2/OIDC** authentication with major providers (GitHub, Google, Azure AD)
- 🚀 **Simple setup** - no complex Istio ext_authz configuration
- 🎯 **Isolated** - each app manages its own authentication
- 🔄 **Portable** - easy to migrate between clusters
- 🌐 **Built-in SSO** - single sign-on across all apps in your domain
- 🎨 **Customizable** - brand your sign-in pages
- 📊 **Observable** - metrics and health checks included

## 📚 Documentation

**Full documentation is available at [https://ianlintner.github.io/authproxy/](https://ianlintner.github.io/authproxy/)**

Quick links:
- [Quick Start Guide](https://ianlintner.github.io/authproxy/getting-started/quickstart/)
- [Architecture Overview](https://ianlintner.github.io/authproxy/architecture/overview/)
- [Adding Apps Guide](https://ianlintner.github.io/authproxy/guide/adding-apps/)
- [Configuration Reference](https://ianlintner.github.io/authproxy/reference/configuration/)

## 🚀 Quick Start

```bash
# 1. Install with Helm
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set oauth.provider=github \
  --set oauth.clientID=your-client-id \
  --set oauth.clientSecret=your-client-secret

# 2. Deploy example app
kubectl apply -k k8s/apps/example-app/

# 3. Visit your app
open https://example-app.example.com
```

See the [Quick Start Guide](https://ianlintner.github.io/authproxy/getting-started/quickstart/) for detailed instructions.

## 📋 Prerequisites

- Kubernetes cluster (1.20+) with kubectl access
- Istio service mesh installed (1.14+)
- Helm 3 installed
- A domain with DNS access
- OAuth application registered with your provider

## 🏗️ Architecture

```
User → Istio Gateway → Service (:4180) → Pod
                                          ├─ oauth2-proxy (:4180)
                                          └─ your-app (:8080)
```

The sidecar pattern places `oauth2-proxy` alongside your application:

1. All traffic first hits oauth2-proxy on port 4180
2. oauth2-proxy checks for valid session cookie
3. If not authenticated → redirects to OAuth provider
4. If authenticated → proxies request to your app on localhost:8080
5. User headers are injected for your app to use

**Benefits:**
- ✅ No complex Istio ext_authz configuration
- ✅ Each app has isolated auth configuration
- ✅ Easy debugging - logs co-located with app
- ✅ Flexible - different OAuth providers per app
- ✅ Portable - apps easily move between clusters

See [Architecture Documentation](https://ianlintner.github.io/authproxy/architecture/overview/) for details.

## 🔧 Usage

### Using Helm Chart (Recommended)

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set cookieDomain=.example.com \
  --set oauth.provider=github \
  --set oauth.clientID=your-client-id \
  --set oauth.clientSecret=your-client-secret \
  --set istio.gateway.tls.credentialName=wildcard-tls
```

See [Helm Chart Documentation](https://ianlintner.github.io/authproxy/guide/helm-chart/) for all options.

### Deploying Applications

See the complete guide at [Adding Apps](https://ianlintner.github.io/authproxy/guide/adding-apps/).

Quick example - add sidecar to existing app:

```bash
./scripts/add-app.sh myapp default 8080 myapp.example.com
```

### Accessing User Information

Your app receives user information via HTTP headers:

```python
# Python/Flask example
from flask import request

@app.route('/')
def index():
    email = request.headers.get('X-Auth-Request-Email')
    user = request.headers.get('X-Auth-Request-User')
    return f'Hello {user} ({email})!'
```

Available headers:
- `X-Auth-Request-User` - Username
- `X-Auth-Request-Email` - Email address
- `X-Auth-Request-Preferred-Username` - Preferred username
- `X-Forwarded-User` - User identifier
- `X-Forwarded-Email` - Email address

## 📖 Documentation

Comprehensive documentation is available at **[https://ianlintner.github.io/authproxy/](https://ianlintner.github.io/authproxy/)**

### Key Topics

- **[Getting Started](https://ianlintner.github.io/authproxy/getting-started/quickstart/)** - Quick start guide
- **[Architecture](https://ianlintner.github.io/authproxy/architecture/overview/)** - How it works
- **[Adding Apps](https://ianlintner.github.io/authproxy/guide/adding-apps/)** - Integrate with your apps
- **[Configuration](https://ianlintner.github.io/authproxy/reference/configuration/)** - All config options
- **[OAuth Providers](https://ianlintner.github.io/authproxy/providers/github/)** - Provider setup guides
- **[Troubleshooting](https://ianlintner.github.io/authproxy/guide/troubleshooting/)** - Common issues

### Building Documentation Locally

```bash
# Install dependencies
pip install -r docs/requirements.txt

# Serve locally
mkdocs serve

# Build static site
mkdocs build
```

## 🔒 Supported OAuth Providers

- **GitHub** - [Setup Guide](https://ianlintner.github.io/authproxy/providers/github/)
- **Google** - [Setup Guide](https://ianlintner.github.io/authproxy/providers/google/)
- **Azure AD / Microsoft Entra** - [Setup Guide](https://ianlintner.github.io/authproxy/providers/azure-ad/)
- **OIDC** - [Setup Guide](https://ianlintner.github.io/authproxy/providers/oidc/)
- And many more supported by oauth2-proxy

## 📁 Repository Structure

```
├── docs/                    # MkDocs documentation
│   ├── getting-started/    # Quick start guides
│   ├── architecture/       # Architecture deep dives with diagrams
│   ├── guide/              # User guides
│   ├── providers/          # OAuth provider setup guides
│   └── reference/          # Configuration reference
├── helm/
│   └── oauth2-sidecar/     # Helm chart for installation
├── k8s/
│   ├── base/               # Base Kubernetes resources
│   │   ├── istio/         # Istio Gateway configuration
│   │   └── oauth2-proxy/  # oauth2-proxy ConfigMaps and templates
│   └── apps/
│       └── example-app/    # Complete working example
├── scripts/
│   ├── add-app.sh         # Add auth to existing apps
│   ├── setup.sh           # Initial setup
│   └── validate.sh        # Validation script
└── examples/              # Example configurations
```

## 🛠️ Development

### Local Documentation

Build and serve the documentation locally:

```bash
pip install -r docs/requirements.txt
mkdocs serve
# Visit http://localhost:8000
```

### Testing

```bash
# Validate Kubernetes manifests
./scripts/validate.sh

# Test OAuth flow
curl -v https://example-app.example.com
```  
Adds oauth2-proxy sidecar to existing deployment:

```bash
./scripts/add-sidecar.sh <app-name> <namespace> <app-port> <domain>

# Example:
./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
```

### validate.sh
Checks infrastructure is properly configured:

```bash
./scripts/validate.sh
```

## 🔍 Troubleshooting

### Check oauth2-proxy sidecar logs

```bash
kubectl logs -n <namespace> <pod-name> -c oauth2-proxy
```

### Check app can't be reached

1. Verify VirtualService routes to port 4180:
   ```bash
   kubectl get virtualservice <app-name> -o yaml
   ```

2. Verify Service exposes port 4180:
   ```bash
   kubectl get svc <app-name>
   ```

3. Check oauth2-proxy sidecar is running:
   ```bash
   kubectl get pod <pod-name> -o jsonpath='{.spec.containers[*].name}'
   ```

### Authentication loop / redirect issues

Check OAUTH2_PROXY_REDIRECT_URL matches your domain:
```bash
kubectl get deployment <app-name> -o yaml | grep REDIRECT_URL
```

### Cookie not persisting

Verify cookie domain is `.cat-herding.net` in ConfigMap

## 📚 Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Detailed architecture and design
- [ADDING_APPS.md](docs/ADDING_APPS.md) - Step-by-step guide for adding auth
- [SETUP.md](docs/SETUP.md) - Detailed setup instructions

## 🔐 Security Notes

- Cookie secret must be 32 bytes, randomly generated
- Use HTTPS only (enforced by cookie_secure = true)
- Session cookies expire after 7 days by default
- All secrets should be stored in Kubernetes secrets (never commit to git!)

## 📝 License

MIT

### Configure OAuth Provider

Edit `k8s/base/oauth2-proxy/secret.yaml` with your provider credentials:

- **GitHub**: Create OAuth App at https://github.com/settings/developers
- **Google**: Create OAuth 2.0 Client at https://console.cloud.google.com
- **Azure AD B2C**: Create app registration in Azure Portal
- **Auth0**: Create application in Auth0 dashboard

**Callback URL**: `https://auth.cat-herding.net/oauth2/callback`

### Custom Login Experience (Tailwind UI)

This deployment now includes a custom Tailwind CSS powered sign-in page with:

- Modern light/dark theme toggle (persisted to `localStorage`)
- Provider selection cards (GitHub active; Google, Microsoft, LinkedIn placeholders)
- Accessible button focus states and subtle motion
- Friendly error page with retry action

You can customize templates in `k8s/base/oauth2-proxy/templates-configmap.yaml`:

```yaml
data:
  sign_in.html: |  # Main login page
  error.html:   |  # Error page when authentication fails
```

If you add more providers (by deploying additional `oauth2-proxy` instances or migrating to an identity aggregator), convert the placeholder buttons into active links pointing at the appropriate start endpoints (usually `/oauth2/start` on the provider-specific auth host).

To disable the custom UI (fallback to default): remove these args from the Deployment:

```yaml
  - --custom-templates-dir=/templates
  - --skip-provider-button=false
```

And delete the templates ConfigMap reference in the volumes & mounts.

### Enabling Additional Providers

`oauth2-proxy` supports one provider per instance. Recommended strategies for multi-provider selection:

1. Run multiple `oauth2-proxy` Deployments (e.g. `oauth2-proxy-github`, `oauth2-proxy-google`) each on its own subdomain and update the login page buttons to link directly to those domains.
2. Use an IdP aggregator (e.g. Auth0, Azure AD B2C) and configure `oauth2-proxy` with `--provider=oidc` to get multiple social logins via a single OIDC issuer.
3. Introduce an internal "auth selector" microservice that issues redirects to provider-specific ingress hosts.

For option (2), update Deployment args:

```yaml
  - --provider=oidc
  - --oidc-issuer-url=https://YOUR_TENANT.b2clogin.com/... (or Auth0/Azure AD issuer)
```

Then adapt `sign_in.html` to remove individual provider cards (the upstream IdP supplies them).

### Template Iteration Workflow

```bash
# Edit template ConfigMap
vim k8s/base/oauth2-proxy/templates-configmap.yaml

# Rebuild manifests locally
kubectl kustomize k8s/base | grep -n 'sign_in.html' | head

# Apply changes
kubectl apply -k k8s/base

# Verify pod picked up new template (may require restart if not rolling update)
kubectl rollout restart deployment/oauth2-proxy -n default
```

### Dark Mode Default

Set default theme to dark by adding to `<body>` tag class list in `sign_in.html` or pre-seeding `localStorage.setItem('theme','dark')`.

### Security Notes for Custom Templates

| Concern | Mitigation |
|---------|------------|
| XSS via template variables | oauth2-proxy only injects controlled context; avoid adding `{{.}}` expansions for untrusted inputs |
| Assets integrity | Tailwind CDN; if stricter CSP required, self-host a compiled CSS bundle |
| Spoofed provider buttons | Clearly mark unavailable providers as disabled until implemented |

Make sure you re-run `./scripts/validate.sh auth.cat-herding.net full` after UI changes to confirm no auth regression.

## 📁 Project Structure

```
authproxy/
├── k8s/
│   ├── base/
│   │   ├── namespace.yaml              # Auth namespace
│   │   ├── oauth2-proxy/               # Central auth proxy
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── secret.yaml.example
│   │   │   └── configmap.yaml
│   │   ├── istio/                      # Istio configuration
│   │   │   ├── gateway.yaml            # Wildcard gateway
│   │   │   ├── ext-authz-filter.yaml   # EnvoyFilter for auth
│   │   │   └── virtualservice-auth.yaml
│   │   └── rbac/
│   └── apps/
│       └── example-app/                # Reference implementation
├── scripts/
│   ├── setup.sh                        # Deploy infrastructure
│   ├── add-app.sh                      # Add auth to new app
│   └── validate.sh                     # Test auth flow
└── docs/
    ├── ARCHITECTURE.md                 # Detailed design
    ├── SETUP.md                        # Step-by-step guide
    └── ADDING_APPS.md                  # App integration guide
```

## 🛠️ Scripts

### setup.sh
Deploys oauth2-proxy, Istio configuration, and validates setup.

```bash
./scripts/setup.sh
```

### add-app.sh
Generates manifests for adding auth to an existing app.

```bash
./scripts/add-app.sh <app-name> <namespace> <port>
# Example: ./scripts/add-app.sh chat chat-ns 3000
```

### validate.sh
Tests the authentication flow end-to-end.

```bash
./scripts/validate.sh myapp.cat-herding.net
```

## 🔍 Troubleshooting

### Check oauth2-proxy logs
```bash
kubectl logs -n default -l app=oauth2-proxy -f
```

### Verify ext_authz filter is active
```bash
kubectl get envoyfilter -n istio-system ext-authz -o yaml
```

### Test auth check endpoint directly
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://oauth2-proxy.default.svc.cluster.local:4180/oauth2/auth
```

### Check if app has auth enabled
```bash
kubectl get deployment -n <namespace> <app> -o jsonpath='{.metadata.labels}'
```

## 📚 Documentation

- [Architecture Details](docs/ARCHITECTURE.md)
- [Setup Guide](docs/SETUP.md)
- [Adding Apps](docs/ADDING_APPS.md)

## 🔒 Security Considerations

- Session cookies are encrypted and HTTP-only
- Cookie domain is `.cat-herding.net` for SSO
- TLS required for all endpoints (enforced by Istio)
- OAuth state parameter prevents CSRF
- Istio mTLS encrypts service-to-service traffic

## 📊 Monitoring & Logging

oauth2-proxy logs include:
- User email/identity
- Requested URL
- Authentication provider
- Timestamp and source IP

Forward logs to Azure Monitor or your logging solution:

```bash
kubectl logs -n default -l app=oauth2-proxy --tail=100 | \
  jq 'select(.msg == "AuthSuccess" or .msg == "AuthFailure")'
```

## 🎓 Learn More

- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Istio External Authorization](https://istio.io/latest/docs/tasks/security/authorization/authz-custom/)
- [Envoy ext_authz Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)

## 📝 License

MIT

## 🤝 Contributing

Contributions welcome! Please test changes in dev overlay before submitting PRs.
