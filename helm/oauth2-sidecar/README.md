# OAuth2 Sidecar Helm Chart

OAuth2 authentication sidecar for Kubernetes applications using oauth2-proxy and Istio.

## TL;DR

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set oauth.provider=github \
  --set oauth.clientID=YOUR_CLIENT_ID \
  --set oauth.clientSecret=YOUR_CLIENT_SECRET \
  --set istio.gateway.tls.credentialName=tls-secret
```

## Introduction

This Helm chart deploys the OAuth2 Sidecar pattern for Kubernetes, enabling easy OAuth2 authentication for your applications using a sidecar container approach. Each application gets its own `oauth2-proxy` container that handles authentication before requests reach your app.

### Features

- 🔐 **OAuth2 Authentication** - Support for GitHub, Google, Azure AD, and generic OIDC
- 🔄 **SSO Enabled** - Single sign-on across all applications under the same domain
- 🚀 **Simple Integration** - Just add a sidecar container to your deployments
- 🎨 **Customizable** - Custom templates, branding, and configuration
- 🛡️ **Istio Integration** - Works seamlessly with Istio service mesh
- 📦 **No External Dependencies** - Stateless, cookie-based sessions

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Istio 1.10+ installed and configured
- OAuth application registered with your provider
- TLS certificate for your domain
- Wildcard DNS pointing to Istio ingress gateway

## Installing the Chart

### 1. Register OAuth Application

First, register an OAuth application with your provider:

**GitHub**: https://github.com/settings/developers
- Callback URL: `https://app.example.com/oauth2/callback`

**Google**: https://console.cloud.google.com/apis/credentials
- Authorized redirect URIs: `https://app.example.com/oauth2/callback`

**Azure AD**: https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps
- Redirect URI: `https://app.example.com/oauth2/callback`

### 2. Create values.yaml

```yaml
# values.yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: github
  clientID: "your-client-id"
  clientSecret: "your-client-secret"
  cookieSecret: "generate-with-openssl-rand-base64-32"

istio:
  enabled: true
  gateway:
    create: true
    tls:
      credentialName: wildcard-tls-secret
```

### 3. Install the chart

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar -f values.yaml
```

Or install with command-line flags:

```bash
helm install oauth2-sidecar ./helm/oauth2-sidecar \
  --set domain=example.com \
  --set oauth.provider=github \
  --set oauth.clientID=xxx \
  --set oauth.clientSecret=yyy \
  --set oauth.cookieSecret=zzz \
  --set istio.gateway.tls.credentialName=wildcard-tls-secret
```

## Configuration

### OAuth Providers

#### GitHub

```yaml
oauth:
  provider: github
  clientID: "xxx"
  clientSecret: "yyy"
  github:
    org: "my-org"  # Optional: restrict to organization
    team: "my-team"  # Optional: restrict to team
```

#### Google

```yaml
oauth:
  provider: google
  clientID: "xxx.apps.googleusercontent.com"
  clientSecret: "yyy"
  google:
    hostedDomain: "example.com"  # Optional: restrict to domain
```

#### Azure AD

```yaml
oauth:
  provider: azure
  clientID: "xxx"
  clientSecret: "yyy"
  azure:
    tenant: "your-tenant-id"
```

#### Generic OIDC

```yaml
oauth:
  provider: oidc
  clientID: "xxx"
  clientSecret: "yyy"
  oidc:
    issuerURL: "https://auth.example.com"
    extraScopes:
      - profile
      - email
```

### Using Existing Secret

Instead of providing credentials in values.yaml:

```yaml
oauth:
  existingSecret: "my-oauth-secret"
```

The secret must contain:
- `client-id`
- `client-secret`
- `cookie-secret`

### Using Existing Istio Gateway

```yaml
istio:
  gateway:
    create: false
    existingGateway: "istio-system/my-gateway"
```

### Custom Templates

```yaml
customTemplates:
  enabled: true
  brandName: "My Company SSO"
  logo: "base64-encoded-logo-here"
```

## Usage

### Adding Authentication to an Application

1. **Add the sidecar container to your Deployment**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: my-app:latest
          ports:
            - containerPort: 8080
        
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
          args:
            - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
            - --http-address=0.0.0.0:4180
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

2. **Create Service pointing to sidecar**:

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

3. **Create VirtualService for routing**:

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
    - match:
        - uri:
            prefix: "/"
      route:
        - destination:
            host: my-app
            port:
              number: 4180
```

4. **Access your app**: https://my-app.example.com

Users will be redirected to OAuth provider for authentication.

## Parameters

### Global Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `domain` | Base domain for applications | `example.com` |
| `cookieDomain` | Cookie domain for SSO | `.example.com` |
| `namespace` | Namespace for resources | `default` |

### OAuth Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `oauth.provider` | OAuth provider (github/google/azure/oidc) | `github` |
| `oauth.clientID` | OAuth client ID | `""` |
| `oauth.clientSecret` | OAuth client secret | `""` |
| `oauth.cookieSecret` | Cookie encryption secret | `""` (auto-generated) |
| `oauth.existingSecret` | Use existing secret | `""` |

### Istio Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `istio.enabled` | Enable Istio integration | `true` |
| `istio.gateway.create` | Create Istio Gateway | `true` |
| `istio.gateway.name` | Gateway name | `oauth2-gateway` |
| `istio.gateway.existingGateway` | Use existing gateway | `""` |
| `istio.gateway.tls.credentialName` | TLS secret name | `""` |

### Sidecar Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sidecar.image.repository` | oauth2-proxy image | `quay.io/oauth2-proxy/oauth2-proxy` |
| `sidecar.image.tag` | oauth2-proxy tag | `v7.6.0` |
| `sidecar.port` | Sidecar listen port | `4180` |
| `sidecar.upstreamPort` | Default app port | `8080` |
| `sidecar.resources` | Resource limits | See values.yaml |

See [values.yaml](values.yaml) for complete list of parameters.

## Upgrading

```bash
helm upgrade oauth2-sidecar ./helm/oauth2-sidecar -f values.yaml
```

## Uninstalling

```bash
helm uninstall oauth2-sidecar
```

Note: This will not delete applications using the sidecar, but they will lose authentication functionality.

## Troubleshooting

### Pods not starting

```bash
kubectl get pods -n default
kubectl logs -n default <pod-name> -c oauth2-proxy
```

### Authentication redirects not working

Check the redirect URL matches your OAuth app configuration:
```bash
kubectl get secret oauth2-proxy-secret -o yaml
```

### 502 Bad Gateway

Ensure your app container port matches `OAUTH2_PROXY_UPSTREAMS`.

### Certificate errors

Verify TLS secret exists and is in the correct namespace:
```bash
kubectl get secret -n istio-system wildcard-tls-secret
```

## Examples

See the [examples](../../examples/) directory for complete working examples:
- Simple application with authentication
- Multi-provider setup
- Custom branding
- External secrets integration

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md).

## License

MIT License - see [LICENSE](../../LICENSE)

## Support

- 📖 [Documentation](https://github.com/ianlintner/authproxy)
- 🐛 [Issue Tracker](https://github.com/ianlintner/authproxy/issues)
- 💬 [Discussions](https://github.com/ianlintner/authproxy/discussions)
