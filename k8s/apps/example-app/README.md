# Example App with OAuth2 Authentication

This directory contains a complete example of an application protected by the oauth2-proxy authentication gateway.

## Key Features

1. **Simple opt-in**: Just add label `auth.cat-herding.net/enabled: "true"` to your Deployment
2. **Automatic authentication**: Istio ext_authz filter checks all requests via oauth2-proxy
3. **User identity headers**: Your app receives authenticated user info in request headers
4. **SSO enabled**: Cookie domain is `.cat-herding.net` so users stay logged in across all subdomains

## Files

- `namespace.yaml`: Creates the example-app namespace with Istio injection
- `deployment.yaml`: Sample app deployment with auth label
- `service.yaml`: ClusterIP service for the app
- `virtualservice.yaml`: Routes `example-app.cat-herding.net` to the app
- `authorization-policy.yaml`: Enforces authentication via ext_authz

## Deployment

```bash
# Deploy the example app
kubectl apply -k .

# Or use kustomize
kustomize build . | kubectl apply -f -
```

## Testing

```bash
# Check deployment status
kubectl get deployment -n example-app

# Check if pods are running
kubectl get pods -n example-app

# Test the app (will redirect to login if not authenticated)
curl -v https://example-app.cat-herding.net

# Check logs
kubectl logs -n example-app -l app=example-app -f
```

## Accessing User Identity

The oauth2-proxy injects these headers into requests to your app:

- `X-Auth-Request-User`: Username from OAuth provider
- `X-Auth-Request-Email`: User's email address
- `X-Auth-Request-Preferred-Username`: Preferred username (if available)
- `Authorization`: Bearer token (if configured)

### Example: Reading headers in your application

**Node.js/Express:**
```javascript
app.get('/', (req, res) => {
  const userEmail = req.headers['x-auth-request-email'];
  const userName = req.headers['x-auth-request-user'];
  
  console.log(`Authenticated user: ${userName} (${userEmail})`);
  
  res.send(`Hello ${userName}!`);
});
```

**Python/Flask:**
```python
@app.route('/')
def index():
    user_email = request.headers.get('X-Auth-Request-Email')
    user_name = request.headers.get('X-Auth-Request-User')
    
    print(f"Authenticated user: {user_name} ({user_email})")
    
    return f"Hello {user_name}!"
```

**Go:**
```go
func handler(w http.ResponseWriter, r *http.Request) {
    userEmail := r.Header.Get("X-Auth-Request-Email")
    userName := r.Header.Get("X-Auth-Request-User")
    
    log.Printf("Authenticated user: %s (%s)", userName, userEmail)
    
    fmt.Fprintf(w, "Hello %s!", userName)
}
```

## Customization

### Add auth to your own app

1. Copy these files to your app directory
2. Update the deployment to use your container image
3. Update service ports to match your app
4. Update the hostname in virtualservice.yaml
5. Keep the `auth.cat-herding.net/enabled: "true"` label

### Exclude specific paths from auth

Edit `authorization-policy.yaml` to add allow rules for health checks:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: example-app-allow-healthcheck
  namespace: example-app
spec:
  selector:
    matchLabels:
      app: example-app
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/health", "/healthz", "/ready"]
```

Apply this before the require-auth policy.

## Troubleshooting

### App not redirecting to login

1. Check if EnvoyFilter is active:
   ```bash
   kubectl get envoyfilter -n istio-system ext-authz -o yaml
   ```

2. Check oauth2-proxy logs:
   ```bash
   kubectl logs -n auth -l app=oauth2-proxy -f
   ```

3. Verify VirtualService is routing correctly:
   ```bash
   kubectl get virtualservice -n example-app example-app -o yaml
   ```

### Getting 503 errors

Check if oauth2-proxy service is reachable:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://oauth2-proxy.auth.svc.cluster.local:4180/ping
```

### User headers not appearing in app

1. Verify oauth2-proxy is configured with `--set-xauthrequest=true`
2. Check that EnvoyFilter includes the headers in `allowed_upstream_headers`
3. Enable debug logging in your app to see all received headers
