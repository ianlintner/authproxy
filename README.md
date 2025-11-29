# AKS OAuth2 Sidecar Authentication

Simple OAuth2 authentication for AKS applications using a **sidecar pattern**. Each application gets its own `oauth2-proxy` container that handles authentication before requests reach your app.

## 🚀 Quick Start

```bash
# 1. Configure your OAuth app credentials
cp k8s/base/oauth2-proxy-sidecar/secret.yaml.example k8s/base/oauth2-proxy-sidecar/secret.yaml
# Edit secret.yaml with your OAuth client ID and secret

# 2. Deploy the base infrastructure
./scripts/setup.sh

# 3. Deploy example app with authentication
kubectl apply -k k8s/apps/example-app/

# 4. Or add authentication to an existing app
./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
```

Your app at `https://myapp.cat-herding.net` is now protected with OAuth2!

## 📋 Prerequisites

- AKS cluster with Istio installed
- Wildcard DNS `*.cat-herding.net` pointing to Istio ingress gateway
- Wildcard TLS certificate for `*.cat-herding.net`
- OAuth application registered (GitHub, Google, Azure AD, etc.)
- `kubectl` configured for cluster access

## 🏗️ Architecture

```
Browser → Istio Gateway → Service (4180) → Pod
                                            ├─ oauth2-proxy (4180)
                                            └─ your-app (8080)
```

### How It Works

1. **Traffic hits Istio Gateway** at `https://myapp.cat-herding.net`
2. **Routes to Service** on port 4180
3. **oauth2-proxy sidecar** receives the request
   - Checks for valid session cookie
   - If not authenticated → redirects to OAuth provider
   - If authenticated → proxies to app container on `localhost:8080`
4. **App receives request** with user headers injected
5. **SSO across all apps** via shared `.cat-herding.net` cookie domain

### Benefits

- ✅ **Simple**: No complex Istio ext_authz configuration
- ✅ **Isolated**: Each app has its own auth configuration
- ✅ **Portable**: Easy to move apps between clusters
- ✅ **Debuggable**: Auth logs co-located with app logs
- ✅ **Flexible**: Different OAuth providers per app

## 🔧 Usage

### Deploy New App with Authentication

See the complete example in `k8s/apps/example-app/`:

```yaml
# Key parts of your deployment:
containers:
- name: oauth2-proxy
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
  ports:
  - containerPort: 4180
  env:
  - name: OAUTH2_PROXY_REDIRECT_URL
    value: "https://myapp.cat-herding.net/oauth2/callback"
  - name: OAUTH2_PROXY_UPSTREAMS
    value: "http://127.0.0.1:8080"
  # ... OAuth credentials from secret

- name: app
  # Your application container
  ports:
  - containerPort: 8080
```

### Add Authentication to Existing App

Use the helper script:

```bash
./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
```

This will:
1. Add oauth2-proxy sidecar to your deployment
2. Update service to expose port 4180
3. Create/update VirtualService
4. Deploy changes

### Access User Identity in Your App

The oauth2-proxy sidecar injects headers with user information:

```go
email := r.Header.Get("X-Auth-Request-Email")
user := r.Header.Get("X-Auth-Request-User")
```

```python
email = request.headers.get('X-Auth-Request-Email')
user = request.headers.get('X-Auth-Request-User')
```

## 🔒 OAuth Provider Setup

### GitHub OAuth App

1. Go to https://github.com/settings/developers
2. Create new OAuth App
3. Set callback URL: `https://your-app.cat-herding.net/oauth2/callback`
4. Copy Client ID and Secret to `k8s/base/oauth2-proxy-sidecar/secret.yaml`

### Google OAuth

1. Go to https://console.cloud.google.com/apis/credentials
2. Create OAuth 2.0 Client ID
3. Set callback URL: `https://your-app.cat-herding.net/oauth2/callback`
4. Update `configmap-sidecar.yaml` to use `provider = "google"`

### Other Providers

oauth2-proxy supports many providers. Update the ConfigMap:
- Azure AD: `provider = "azure"`
- OIDC: `provider = "oidc"` + `oidc_issuer_url`
- See: https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider

## 📁 Project Structure

```
k8s/
├── base/
│   ├── istio/
│   │   └── gateway.yaml              # Istio Gateway for *.cat-herding.net
│   └── oauth2-proxy-sidecar/
│       ├── configmap-sidecar.yaml    # OAuth2 proxy configuration
│       ├── secret.yaml.example       # OAuth credentials template
│       └── sidecar-template.yaml     # Container spec template
└── apps/
    └── example-app/          # Complete example
        ├── deployment.yaml            # App + oauth2-proxy sidecar
        ├── service.yaml               # Service on port 4180
        └── virtualservice.yaml        # Routes traffic to sidecar

scripts/
├── setup.sh                          # Deploy base infrastructure
├── add-sidecar.sh                    # Add auth to existing app
└── validate.sh                       # Validate setup
```

## 🛠️ Scripts

### setup.sh
Deploys base infrastructure:
- OAuth2 sidecar ConfigMap
- Istio Gateway
- Validates prerequisites

```bash
./scripts/setup.sh
```

### add-sidecar.sh  
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
