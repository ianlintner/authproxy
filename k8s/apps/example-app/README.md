# Example App with OAuth2 Proxy Sidecar

This example demonstrates how to deploy an application with OAuth2 authentication using the sidecar pattern.

## Architecture

```
Browser → Istio Gateway → Service (port 4180) → Pod
                                                  ├─ oauth2-proxy (port 4180)
                                                  └─ app (port 8080)
```

The oauth2-proxy sidecar:
1. Receives all traffic on port 4180
2. Checks for valid OAuth session cookie
3. If not authenticated: redirects to OAuth provider
4. If authenticated: proxies request to app container on localhost:8080
5. Injects user headers (X-Auth-Request-Email, etc.)

## Files

- `deployment.yaml` - Pod with oauth2-proxy sidecar + nginx app container
- `service.yaml` - Service exposing port 4180 (oauth2-proxy)
- `virtualservice.yaml` - Routes traffic from example-app.cat-herding.net to service
- `configmap-web.yaml` - Nginx configuration and HTML with logout button
- `namespace.yaml` - Namespace with Istio injection enabled
- `kustomization.yaml` - Kustomize configuration

## Deploy

```bash
# 1. Create OAuth secret (if not already exists)
kubectl apply -f ../../base/oauth2-proxy-sidecar/secret.yaml

# 2. Deploy example app
kubectl apply -k .
```

## Test

1. Visit https://example-app.cat-herding.net
2. You'll be redirected to GitHub/Google/your OAuth provider
3. After login, you'll be redirected back to the app
4. Cookie is set for `.cat-herding.net` domain (SSO across all apps)
5. Click **Sign Out** button to logout and clear the session

## Logout Functionality

The example app includes a logout button that:
- Redirects to `/oauth2/sign_out?rd=<return_url>`
- Clears the OAuth session cookie
- Returns user to the sign-in page

The logout endpoint is handled by oauth2-proxy and works automatically with any application using the sidecar pattern.

## Customize for Your App

1. Copy this directory: `cp -r example-app my-app`
2. Edit `deployment.yaml`:
   - Change `OAUTH2_PROXY_REDIRECT_URL` to your domain
   - Change `OAUTH2_PROXY_UPSTREAMS` to your app's port
   - Replace the `app` container with your application
3. Edit `virtualservice.yaml`: Change hostname
4. Edit `service.yaml`: Change metadata.name
5. Apply: `kubectl apply -k my-app/`
