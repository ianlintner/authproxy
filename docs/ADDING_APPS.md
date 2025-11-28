# Adding Apps to Authentication Gateway

This guide shows you how to add OAuth2 authentication to your existing applications in the AKS cluster.

## Quick Start

### Option 1: Use the Helper Script (Recommended)

```bash
./scripts/add-app.sh <app-name> <namespace> <port>
```

**Example**:
```bash
./scripts/add-app.sh chat default 3000
```

This automatically generates:
- VirtualService for routing
- AuthorizationPolicy for authentication
- kustomization.yaml for deployment
- README.md with instructions

Then apply:
```bash
kubectl apply -k k8s/apps/chat/
```

### Option 2: Manual Configuration

Follow the steps below to manually add authentication to your app.

## Prerequisites

- Your application is already deployed in the cluster
- Your application has a Kubernetes Service
- DNS subdomain is configured (e.g., `myapp.cat-herding.net`)
- Authentication infrastructure is deployed (run `./scripts/setup.sh` first)

## Step-by-Step Guide

### 1. Add Label to Your Deployment

Edit your application's Deployment to include the auth label:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
    auth.cat-herding.net/enabled: "true"  # Add this line
spec:
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        auth.cat-herding.net/enabled: "true"  # Add this line too
    spec:
      containers:
      - name: myapp
        image: myregistry/myapp:v1.0
        ports:
        - containerPort: 8080
```

Apply the change:
```bash
kubectl apply -f myapp-deployment.yaml
```

### 2. Create VirtualService

Create a VirtualService to route traffic from your subdomain to your app:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
    auth.cat-herding.net/enabled: "true"
spec:
  hosts:
  - "myapp.cat-herding.net"
  gateways:
  - istio-system/cat-herding-gateway
  http:
  - route:
    - destination:
        host: myapp.default.svc.cluster.local
        port:
          number: 8080
```

**Important**: Replace:
- `myapp` with your app name
- `myapp.cat-herding.net` with your subdomain
- `8080` with your app's port

Apply:
```bash
kubectl apply -f myapp-virtualservice.yaml
```

### 3. Create AuthorizationPolicy

Create an AuthorizationPolicy to enforce authentication:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: myapp-require-auth
  namespace: default
  labels:
    app: myapp
    auth.cat-herding.net/enabled: "true"
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
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
```

Apply:
```bash
kubectl apply -f myapp-authorizationpolicy.yaml
```

### 4. Test Authentication

```bash
# Test with curl
curl -v https://myapp.cat-herding.net

# You should see a 302 redirect to the OAuth provider
```

Open in browser:
```
https://myapp.cat-herding.net
```

You should be redirected to GitHub/Google/etc. for login.

## Reading User Identity in Your App

Once authenticated, your application receives user information in HTTP headers:

### Available Headers

- `X-Auth-Request-User`: Username from OAuth provider
- `X-Auth-Request-Email`: User's email address  
- `X-Auth-Request-Preferred-Username`: Preferred username (GitHub, etc.)
- `Authorization`: Bearer access token (if configured)

### Code Examples

#### Node.js / Express

```javascript
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  const userEmail = req.headers['x-auth-request-email'];
  const userName = req.headers['x-auth-request-user'];
  const preferredUsername = req.headers['x-auth-request-preferred-username'];
  
  console.log(`Authenticated user: ${userName} (${userEmail})`);
  
  res.send(`
    <h1>Welcome ${userName}!</h1>
    <p>Email: ${userEmail}</p>
    <p>Username: ${preferredUsername}</p>
  `);
});

app.listen(3000);
```

#### Python / Flask

```python
from flask import Flask, request

app = Flask(__name__)

@app.route('/')
def index():
    user_email = request.headers.get('X-Auth-Request-Email', 'Unknown')
    user_name = request.headers.get('X-Auth-Request-User', 'Unknown')
    preferred_username = request.headers.get('X-Auth-Request-Preferred-Username', 'Unknown')
    
    print(f"Authenticated user: {user_name} ({user_email})")
    
    return f"""
        <h1>Welcome {user_name}!</h1>
        <p>Email: {user_email}</p>
        <p>Username: {preferred_username}</p>
    """

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

#### Go

```go
package main

import (
    "fmt"
    "log"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    userEmail := r.Header.Get("X-Auth-Request-Email")
    userName := r.Header.Get("X-Auth-Request-User")
    preferredUsername := r.Header.Get("X-Auth-Request-Preferred-Username")
    
    log.Printf("Authenticated user: %s (%s)", userName, userEmail)
    
    fmt.Fprintf(w, `
        <h1>Welcome %s!</h1>
        <p>Email: %s</p>
        <p>Username: %s</p>
    `, userName, userEmail, preferredUsername)
}

func main() {
    http.HandleFunc("/", handler)
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

#### Java / Spring Boot

```java
@RestController
public class WelcomeController {
    
    @GetMapping("/")
    public String index(
        @RequestHeader("X-Auth-Request-Email") String email,
        @RequestHeader("X-Auth-Request-User") String username,
        @RequestHeader(value = "X-Auth-Request-Preferred-Username", required = false) String preferredUsername
    ) {
        System.out.println("Authenticated user: " + username + " (" + email + ")");
        
        return String.format(
            "<h1>Welcome %s!</h1><p>Email: %s</p><p>Username: %s</p>",
            username, email, preferredUsername
        );
    }
}
```

## Advanced Configuration

### Exclude Paths from Authentication

If you need to allow unauthenticated access to specific paths (e.g., health checks), create an additional AuthorizationPolicy:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: myapp-allow-healthcheck
  namespace: default
spec:
  selector:
    matchLabels:
      app: myapp
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/health", "/healthz", "/ready", "/readyz", "/metrics"]
```

Apply this **before** the require-auth policy:
```bash
kubectl apply -f myapp-allow-healthcheck.yaml
kubectl apply -f myapp-require-auth.yaml
```

### Custom Timeout Configuration

Adjust timeouts in your VirtualService:

```yaml
spec:
  http:
  - route:
    - destination:
        host: myapp.default.svc.cluster.local
    timeout: 60s  # Increase for long-running requests
    retries:
      attempts: 3
      perTryTimeout: 20s
```

### Multiple Namespaces

If your app is in a different namespace:

```bash
# Create the VirtualService and AuthorizationPolicy in your app's namespace
./scripts/add-app.sh myapp my-namespace 8080

# Apply
kubectl apply -k k8s/apps/myapp/
```

Update the generated files to use `my-namespace` instead of `default`.

## Testing Your Integration

### 1. Verify Configuration

```bash
# Check VirtualService
kubectl get virtualservice -n default myapp -o yaml

# Check AuthorizationPolicy
kubectl get authorizationpolicy -n default myapp-require-auth -o yaml

# Check if label is present
kubectl get deployment -n default myapp -o jsonpath='{.metadata.labels}'
```

### 2. Test Authentication Flow

```bash
# Test with validation script
./scripts/validate.sh myapp.cat-herding.net

# Manual test
curl -v https://myapp.cat-herding.net
# Should return 302 redirect to OAuth provider
```

### 3. Test in Browser

1. Open: `https://myapp.cat-herding.net`
2. You should be redirected to OAuth login
3. After login, you should see your app
4. Check developer tools → Network → Headers for user headers

### 4. Debug Headers

Deploy a header echo service to see all headers:

```bash
kubectl run header-echo --image=ealen/echo-server:latest -n default
kubectl expose pod header-echo --port=80 --target-port=80 -n default

# Add auth to it
./scripts/add-app.sh header-echo default 80
kubectl apply -k k8s/apps/header-echo/

# Access it
open https://header-echo.cat-herding.net
```

## Troubleshooting

### Issue: App redirects but shows 404

**Cause**: VirtualService not configured correctly

**Fix**:
```bash
# Check if VirtualService exists
kubectl get virtualservice -n default -o wide

# Verify hostname and service name
kubectl get virtualservice myapp -n default -o yaml
```

### Issue: No redirect to login page

**Cause**: AuthorizationPolicy not applied or label missing

**Fix**:
```bash
# Check if AuthorizationPolicy exists
kubectl get authorizationpolicy -n default

# Verify label on deployment
kubectl get deployment myapp -n default -o jsonpath='{.metadata.labels}' | grep auth

# If missing, add the label
kubectl label deployment myapp -n default auth.cat-herding.net/enabled=true
```

### Issue: User headers not appearing in app

**Cause**: EnvoyFilter or oauth2-proxy misconfiguration

**Fix**:
```bash
# Check oauth2-proxy logs
kubectl logs -n default -l app=oauth2-proxy | grep -i "x-auth-request"

# Verify EnvoyFilter includes headers
kubectl get envoyfilter -n istio-system ext-authz -o yaml | grep -A 10 allowed_upstream_headers

# Test with header echo app (see above)
```

### Issue: 503 Service Unavailable

**Cause**: oauth2-proxy is down or unreachable

**Fix**:
```bash
# Check oauth2-proxy status
kubectl get pods -n default -l app=oauth2-proxy

# Check oauth2-proxy logs
kubectl logs -n default -l app=oauth2-proxy

# Restart if needed
kubectl rollout restart deployment/oauth2-proxy -n default
```

## Removing Authentication

To disable authentication for an app:

```bash
# Delete the AuthorizationPolicy
kubectl delete authorizationpolicy myapp-require-auth -n default

# Remove the label (optional)
kubectl label deployment myapp -n default auth.cat-herding.net/enabled-

# The app will still be accessible but without authentication
```

To completely remove an app's auth configuration:

```bash
# Delete all auth resources
kubectl delete -k k8s/apps/myapp/

# Keep only the VirtualService if you still want routing
kubectl apply -f k8s/apps/myapp/virtualservice.yaml
```

## Best Practices

1. **Always test in dev first**: Create a test subdomain like `myapp-dev.cat-herding.net`

2. **Use health check exclusions**: Allow `/health` and `/ready` without auth

3. **Log user activity**: Your app should log who accessed what:
   ```javascript
   console.log(`${userEmail} accessed ${req.path} at ${new Date()}`);
   ```

4. **Handle missing headers gracefully**: Not all requests may have headers
   ```javascript
   const userEmail = req.headers['x-auth-request-email'] || 'anonymous';
   ```

5. **Don't trust headers blindly**: Headers are set by oauth2-proxy, but validate important operations

6. **Monitor authentication metrics**: Watch for auth failures in oauth2-proxy logs

7. **Document user identity usage**: Make it clear which headers your app uses

## Examples

See the `k8s/apps/example-app/` directory for a complete working example with:
- Deployment with auth label
- Service configuration
- VirtualService routing
- AuthorizationPolicy enforcement
- README with instructions

## Getting Help

- View oauth2-proxy logs: `kubectl logs -n default -l app=oauth2-proxy -f`
- Run validation: `./scripts/validate.sh myapp.cat-herding.net`
- Check Istio config: `kubectl get virtualservice,authorizationpolicy -n default`
- Review architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- Setup guide: [SETUP.md](SETUP.md)

## Next Steps

- Implement user activity logging
- Set up monitoring and alerts
- Configure additional OAuth providers
- Add role-based access control (RBAC)
- Implement session timeout customization
